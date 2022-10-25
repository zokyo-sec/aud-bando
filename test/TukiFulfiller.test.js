const TukiFulfillerV1 = artifacts.require("TukiFulfillerV1");
const { deployProxy, upgradeProxy } = require('@openzeppelin/truffle-upgrades');

const { expect, assert } = require('chai');

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A"
const REVERT_ERROR_PREFIX = "Returned error: VM Exception while processing transaction:";

let fulfillerContract;

contract("TukiFulfillerV1", function (accounts) {
  
  before(async () => {
    fulfillerContract = await deployProxy(TukiFulfillerV1);
  });

  describe("Upgradeability", async () => {
    it("should have transferred ownership to sender", async () => {
      assert.equal(await fulfillerContract.owner(), accounts[0]);
    });

    it("should have upgraded to new implementation", async () => {
        v2 = await upgradeProxy(fulfillerContract.address, UpgradeTester);
        assert.equal(await v2.isUpgrade(), true);
        assert.equal(v2.address, fulfillerContract.address);
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
});
