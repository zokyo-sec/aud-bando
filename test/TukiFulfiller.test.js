const TukiFulfillerV1 = artifacts.require("TukiFulfillerV1");

const { expect, assert } = require('chai');

const tokens = (n) => {
  return web3.utils.toWei(n, 'ether');
}

contract("TukiFulfillerV1", function (accounts) {
  let fiatToken;

  /*before(async () => {
    fiatToken = await FiatBacked.new();
    await fiatToken.initialize(
      'NanchesV0',
      'NAN',
      'MXN',
      18,
      accounts[0],
      accounts[0],
      accounts[0],
    );
    await fiatToken.configureMinter(accounts[0], tokens('5000'));
  });

  describe("FiatBackedToken Tests", async () => {

    it("should be initialized with data", async () => {
      assert.equal(await fiatToken.totalSupply(), 0)
      assert.equal(await fiatToken.name(), 'NanchesV0')
      assert.equal(await fiatToken.masterMinter(), accounts[0])
      assert.equal(await fiatToken.owner(), accounts[0])
      assert.equal(await fiatToken.currency(), 'MXN')
    });

    it("should not be able to be initialized again", async () => {
      try {
        await fiatToken.initialize(
          'NanchesV0',
          'NAN',
          'MXN',
          18,
          accounts[0],
          accounts[0],
          accounts[0],
        );
      } catch(e) {
        return assert.equal(
          e.message,
          'Returned error: VM Exception while processing transaction: revert FiatBackedToken: contract is already initialized -- Reason given: FiatBackedToken: contract is already initialized.'
        );
      }
    });

    it("should allow us to mint some tokens", async () => {
      assert.equal(await fiatToken.isMinter(accounts[0]), true);
      await fiatToken.mint(accounts[0], tokens('1000'));
      const supply = await fiatToken.totalSupply();
      assert.equal(supply.toString(), tokens('1000'));
    });

    it("should allow us to burn some tokens", async () => {
      assert.equal(await fiatToken.isMinter(accounts[0]), true);
      await fiatToken.burn(tokens('1000'));
      const supply = await fiatToken.totalSupply();
      assert.equal(supply.toString(),'0');
    });

    it("should not allow to mint if allowance is exceeded.", async () => {
      try {
        assert.equal(await fiatToken.isMinter(accounts[1]), false);
        await fiatToken.mint(accounts[1], tokens('10000'));
      } catch (e) {
        return assert.equal(
          e.message,
          'Returned error: VM Exception while processing transaction: revert FiatBacked: mint amount exceeds minterAllowance -- Reason given: FiatBacked: mint amount exceeds minterAllowance.'
        );
      }
    });

  });*/
});
