const TukiRouterV1 = artifacts.require("TukiRouterV1");
const UpgradeTester = artifacts.require("RouterUpgradeTester");
const RegexValidator = artifacts.require("TwelveDigitsValidator");

const { deployProxy, upgradeProxy } = require('@openzeppelin/truffle-upgrades');
const { expect, assert } = require('chai');

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A"

let routerContract;
let regexValidator;
let v2;

contract("TukiRouterV1", function (accounts) {

  before(async () => {
    routerContract = await deployProxy(TukiRouterV1);
    regexValidator = await RegexValidator.new();
  });

  describe("Upgradeability", async () => {
    it("should have transferred ownership to sender", async () => {
      assert.equal(await routerContract.owner(), accounts[0]);
    });

    it("should have upgraded to new implementation", async () => {
        v2 = await upgradeProxy(routerContract.address, UpgradeTester);
        assert.equal(await v2.isUpgrade(), true);
        assert.equal(v2.address, routerContract.address);
    });
  });

  describe("Ownability", async () => {
    it("should only allow an owner for test method", async () => {
      try {
        assert.notEqual(await v2.owner(), accounts[1]);
        const response = await v2.isUpgrade({ from: accounts[1] });
        assert.notEqual(response, true);
      } catch(err) {
        assert.equal(
          err.message,
          "Returned error: VM Exception while processing transaction: revert Ownable: caller is not the owner"
        );
      }
    });

    it("should allow owner to transfer ownership", async () => {
        await v2.transferOwnership(accounts[1]);
        assert.equal(await v2.owner(), accounts[1]);
    });
  });

  describe("Route to service", async () => {
    it("should not allow a non-owner to set up a service", async () => {
      try {
        assert.notEqual(await v2.owner(), accounts[0]);
        const response = await v2.setService(1, DUMMY_ADDRESS, DUMMY_ADDRESS);
      } catch(err) {
        assert.equal(
          err.reason,
          "Ownable: caller is not the owner"
        );
      }
    }); 

    it("should allow an owner to set up a service", async () => {
      assert.equal(await v2.owner(), accounts[1]);
      await v2.setService(1, DUMMY_ADDRESS, regexValidator.address, { from: accounts[1] });
      assert.deepEqual(await v2.serviceOf(1), [DUMMY_ADDRESS, regexValidator.address]);
    });

    it("should fail when service id is not set by owner", async () => {
      try {
        await v2.requestService(2, "012345678", false, DUMMY_ADDRESS, 30000, {value: 1000});
      } catch(err) {
        assert.equal(err.reason, "Service ID is not supported.");
      }
    });

    it("should fail for invalid identifier", async () => {
    });
  });
});
