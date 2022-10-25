const TukiRouterV1 = artifacts.require("TukiRouterV1");
const UpgradeTester = artifacts.require("RouterUpgradeTester");
const RegexValidator = artifacts.require("TwelveDigitsValidator");

const { deployProxy, upgradeProxy } = require('@openzeppelin/truffle-upgrades');
const { expect, assert } = require('chai');

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A"
const REVERT_ERROR_PREFIX = "Returned error: VM Exception while processing transaction:";

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

  describe("Pausability", async () => {
    it("should only allow an owner to pause the contract", async () => {
      try {
        assert.equal(await v2.owner(), accounts[0]);
        await v2.pause({from: accounts[1]});
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.equal(
          err.message,
          `${REVERT_ERROR_PREFIX} revert Ownable: caller is not the owner`
        );
      }
      await v2.pause();
      assert.equal(await v2.paused(), true);
    });

    it("should only allow an owner to unpause the contract", async () => {
      try {
        assert.equal(await v2.owner(), accounts[0]);
        await v2.unpause({from: accounts[1]});
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.equal(
          err.message,
          `${REVERT_ERROR_PREFIX} revert Ownable: caller is not the owner`
        );
      }
      await v2.unpause();
      assert.equal(await v2.paused(), false);
    });
  });

  describe("Ownability", async () => {
    it("should only allow an owner for test method", async () => {
      try {
        assert.notEqual(await v2.owner(), accounts[1]);
        const response = await v2.isUpgrade({ from: accounts[1] });
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.equal(
          err.message,
          `${REVERT_ERROR_PREFIX} revert Ownable: caller is not the owner`
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
        await v2.setService(1, DUMMY_ADDRESS, DUMMY_ADDRESS);
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.equal(
          err.message,
          `${REVERT_ERROR_PREFIX} revert Ownable: caller is not the owner`
        );
      }
    }); 

    it("should allow an owner to set up a service", async () => {
      assert.equal(await v2.owner(), accounts[1]);
      await v2.setService(1, DUMMY_ADDRESS, regexValidator.address, { from: accounts[1] });
      assert.deepEqual(await v2.serviceOf(1), [DUMMY_ADDRESS, regexValidator.address]);
    });

    it("should fail to add service when validator is not set or invalid.", async () => {
      try {
        assert.equal(await v2.owner(), accounts[1]);
        await v2.setService(1, DUMMY_ADDRESS, null, { from: accounts[1] });
        throw new Error("This should have thrown lines ago.");
      } catch (err) {
        assert.hasAnyKeys(err, ["code"]);
        assert.equal(err.code, "INVALID_ARGUMENT");
      }

      try {
        assert.equal(await v2.owner(), accounts[1]);
        await v2.setService(1, DUMMY_ADDRESS, 10, { from: accounts[1] });
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.hasAnyKeys(err, ["code"]);
        assert.equal(err.code, "INVALID_ARGUMENT");
      }
    });

    it("should fail when service id is not set by owner", async () => {
      try {
        await v2.requestService(2, "012345678", 30000, {from: accounts[1], value: 1});
        throw new Error("This should have thrown lines ago.")
      } catch(err) {
        assert.equal(
          err.message,
          `${REVERT_ERROR_PREFIX} revert Service ID is not supported`
        );
      }
    });

    it("should fail for when amount is zero.", async () => {
      try {
        await v2.requestService(1, "012345678", 30000, {from: accounts[0], value: 0});
        throw new Error("This should have thrown lines ago.")
      } catch(err) {
        assert.equal(
          err.message,
          `${REVERT_ERROR_PREFIX} revert Amount must be greater than zero`
        );
      }
    });

    it("should fail when the validator doesnt match", async () => {
      try {
        await v2.requestService(1, "012345678", 30000, {from: accounts[0], value: web3.utils.toWei("1000", "ether")});
        throw new Error("This should have thrown lines ago.")
      } catch(err) {
        assert.equal(
          err.message,
          `${REVERT_ERROR_PREFIX} revert The service identifier failed to validate`
        );
      }

      try {
        await v2.requestService(1, "01234567891234", 30000, {from: accounts[0], value: web3.utils.toWei("1000", "ether")});
        throw new Error("This should have thrown lines ago.")
      } catch(err) {
        assert.equal(
          err.message,
          `${REVERT_ERROR_PREFIX} revert The service identifier failed to validate`
        );
      }
    });

    it("should fail with insufficient funds error", async () => {
      try {
        await v2.requestService(1, "012345678912", 30000, {value: web3.utils.toWei("1000", "ether")});
        throw new Error("This should have thrown lines ago.")
      } catch(err) {
        assert.equal(
          new String(err.message).startsWith("Returned error: sender doesn't have enough funds to send tx. The upfront cost is:"),
          true
        );
      }
    });

    it("should send to escrow", async () => {
        throw new Error("TBD");
    });
  });
});
