const ToppiRouterV1 = artifacts.require("ToppiRouterV1");

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
contract("ToppiRouterV1", function (accounts) {

  before(async () => {
    fiatToken = await deployProxy(
        ToppiRouterV1,
        { initializer: 'initialize' }
    );
  });

  describe("ToppiRouter Upgreadeability Tests", async () => {
    it("should have transferred ownership", async () => {
      console.log(accounts);
      //TODO: Assert that ownership was transferred.
      /* this is just an example.
      assert.equal(await fiatToken.totalSupply(), 0)
      assert.equal(await fiatToken.name(), 'NanchesV0')
      assert.equal(await fiatToken.masterMinter(), accounts[0])
      assert.equal(await fiatToken.owner(), accounts[0])
      assert.equal(await fiatToken.currency(), 'MXN')*/
    });
  });
});
