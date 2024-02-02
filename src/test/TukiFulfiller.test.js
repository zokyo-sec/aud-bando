const { expect, assert } = require("chai");
const { ethers, upgrades } = require("hardhat");

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A"
const REVERT_ERROR_PREFIX = "Returned error: VM Exception while processing transaction:";

/**
* @dev Anybody can submit a fulfillment request through a router.
* struct FulFillmentRequest {
*  address payer; // address of payer
* uint256 weiAmount; // address of the subject, the recipient of a successful verification
*  uint256 fiatAmount; // fiat amount to be charged for the fufillable
*  uint256 feeAmount; // fee amount in wei
*  string serviceRef; // identifier required to route the payment to the user's destination
*}
**/
const DUMMY_FULFILLMENTREQUEST = {
  payer: DUMMY_ADDRESS,
  weiAmount: 0,
  fiatAmount: 10,
  serviceRef: "01234XYZ"
}

let escrow;
let fulfillerContract;
let owner;
let beneficiary;
let fulfiller;
let router;

describe("TukiFulfillableV1", () => {
  
  before(async () => {
    [owner, beneficiary, fulfiller, router] = await ethers.getSigners();
    fulfillerContract = await ethers.deployContract('TukyFulfillableV1', [
      beneficiary, 1, ethers.parseUnits('1'), router, fulfiller
    ]);
    await fulfillerContract.waitForDeployment();
    escrow = fulfillerContract.attach(await fulfillerContract.getAddress())
  });

  describe("Fulfillment logic", async () => {

    it("should set the beneficiary correctly", async () => {
      const b = await escrow.beneficiary();
      expect(b).to.be.a.properAddress
      expect(b).to.be.equal(beneficiary)
    });

    it("should set the fulfiller correctly", async () => {
      const f = await escrow.fulfiller();
      expect(f).to.be.a.properAddress
      expect(f).to.be.equal(fulfiller)
    });

    it("should not allow a non-owner to withdraw a refund", async () => {
      try {
        assert.notEqual(await fulfillerContract.owner(), accounts[0]);
        const response = await fulfillerContract.withdrawRefund(accounts[0]);
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.equal(
          err.message,
          `${REVERT_ERROR_PREFIX} revert Ownable: caller is not the owner`
        );
      }
    });

    it("should not allow to refund when payee has no authorized balance.", async () => {
      try {
        const response = await fulfillerContract.withdrawRefund(accounts[1], {from: accounts[1]});
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.equal(
          err.message,
          `${REVERT_ERROR_PREFIX} revert Address is not allowed any refunds`
        );
      }
    });

    it("should not allow a payable deposit coming from any random address.", async () => {
      try {
        assert.notEqual(await fulfillerContract.owner(), accounts[0]);
        const response = await fulfillerContract.deposit(DUMMY_FULFILLMENTREQUEST, {value: web3.utils.toWei("10", "ether")});
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.equal(
          err.message,
          `${REVERT_ERROR_PREFIX} revert Ownable: caller is not the owner`
        );
      }
    });

    it("should allow a payable deposit coming from an owner.", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = accounts[2];
      DUMMY_FULFILLMENTREQUEST.feeAmount = web3.utils.toWei("100", "wei");
      DUMMY_FULFILLMENTREQUEST.weiAmount = web3.utils.toWei("1000", "wei");
      const response = await fulfillerContract.deposit(DUMMY_FULFILLMENTREQUEST, {from: accounts[1], value: web3.utils.toWei("1100", "wei")});
      const postBalanace = await web3.eth.getBalance(fulfillerContract.address);
      const tx = await web3.eth.getTransaction(response.tx);
      const BNresponse = await fulfillerContract.depositsOf(accounts[2]);
      assert.equal(BNresponse.toString(), "1100");
      assert.equal(postBalanace, "1100");
      assert.equal(tx.value, "1100");
    });
  });
});
