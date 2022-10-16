const TukiRouterV1 = artifacts.require("TukiRouterV1");
const { deployProxy } = require('@openzeppelin/truffle-upgrades');
const { expect, assert } = require('chai');

const tokens = (n) => {
  return web3.utils.toWei(n, 'ether');
}

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
contract("TukiRouterV1", function (accounts) {

  before(async () => {
    routerContract = await deployProxy(TukiRouterV1);
  });

  describe("TukiRouter Upgreadeability Tests", async () => {
    it("should have transferred ownership to sender", async () => {
      console.log(accounts);
      assert.equal(await routerContract.owner(), accounts[0]);
    });
  });
});
