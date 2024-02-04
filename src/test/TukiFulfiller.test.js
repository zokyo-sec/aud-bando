const { expect, assert } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { v4: uuidv4 } = require('uuid');

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A"

const DUMMY_FULFILLMENTREQUEST = {
  payer: DUMMY_ADDRESS,
  weiAmount: 100,
  fiatAmount: 10,
  serviceRef: "01234XYZ"
}
 
const SUCCESS_FULFILLMENT_RESULT = {
  status: 1,
  weiAmount: 100,
  externalID: uuidv4(),
  receiptURI: 'https://test.com',
  id: null,
}

const INVALID_FULFILLMENT_RESULT = {
  status: 3,
  weiAmount: 100,
  externalID: uuidv4(),
  receiptURI: 'https://test.com',
  id: null,
}

const FAILED_FULFILLMENT_RESULT = {
  status: 0,
  weiAmount: 100,
  externalID: uuidv4(),
  receiptURI: 'https://test.com',
  id: null,
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
      beneficiary, 1, ethers.parseUnits('1', 'wei'), router, fulfiller
    ]);
    await fulfillerContract.waitForDeployment();
    escrow = fulfillerContract.attach(await fulfillerContract.getAddress())
  });

  describe("Configuration Specs", async () => {
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
  });

  describe("Deposit Specs", () => {
    it("should not allow a payable deposit coming from any random address.", async () => {
      await expect(
        escrow.deposit(DUMMY_FULFILLMENTREQUEST, {value: ethers.parseUnits("10", "ether")})
      ).to.be.revertedWith('Caller is not the router');
    });

    it("should allow a payable deposit coming from the router.", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = DUMMY_ADDRESS;
      DUMMY_FULFILLMENTREQUEST.weiAmount = ethers.parseUnits("100", "wei");
      const fromRouter = await escrow.connect(router);
      const response = await fromRouter.deposit(DUMMY_FULFILLMENTREQUEST, { value: ethers.parseUnits("101", "wei")});
      const postBalanace = await ethers.provider.getBalance(await escrow.getAddress());
      const tx = await ethers.provider.getTransaction(response.hash);
      const BNresponse = await fulfillerContract.depositsOf(DUMMY_ADDRESS);
      assert.equal(BNresponse.toString(), "101");
      assert.equal(postBalanace, "101");
      assert.equal(tx.value, "101");
    });

    it("should emit a DepositReceived event", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = DUMMY_ADDRESS;
      DUMMY_FULFILLMENTREQUEST.weiAmount = ethers.parseUnits("100", "wei");
      const fromRouter = await escrow.connect(router);
      await expect(
        fromRouter.deposit(DUMMY_FULFILLMENTREQUEST, { value: ethers.parseUnits("101", "wei")})
      ).to.emit(escrow, "DepositReceived")
    });

    it("should persist unique fulfillment records on the blockchain", async () => {
      const payerRecordIds = await escrow.recordsOf(DUMMY_ADDRESS);
      const record1 = await escrow.record(payerRecordIds[0]);
      expect(record1[0]).to.be.equal(1); //record ID
      expect(record1[2]).to.be.equal(await fulfiller.getAddress()); //fulfiller
      expect(record1[4]).to.be.equal(DUMMY_ADDRESS); //payer address
      expect(record1[10]).to.be.equal(2); //status. 2 = PENDING
    });
  });

  describe("Register Fulfillment Specs", () => {
    it("should only allow to register a fulfillment via the manager", async () => {
      const fromRouter = await escrow.connect(router);
      const payerRecordIds = await fromRouter.recordsOf(DUMMY_ADDRESS);
      SUCCESS_FULFILLMENT_RESULT.id = payerRecordIds[0];
      await expect(
        fromRouter.registerFulfillment(SUCCESS_FULFILLMENT_RESULT)
      ).to.be.revertedWith('Caller is not the manager');
      await expect(
        escrow.registerFulfillment(SUCCESS_FULFILLMENT_RESULT)
      ).not.to.be.reverted;
      const record = await escrow.record(payerRecordIds[0]);
      expect(record[10]).to.be.equal(1);
    });

    it("should not allow to register a fulfillment with an invalid status.", async () => {
      const payerRecordIds = await escrow.recordsOf(DUMMY_ADDRESS);
      INVALID_FULFILLMENT_RESULT.id = payerRecordIds[1];
      await expect(
        escrow.registerFulfillment(INVALID_FULFILLMENT_RESULT)
      ).to.be.reverted;
      const record = await escrow.record(payerRecordIds[1]);
      expect(record[10]).to.be.equal(2);
    });

    it("should authorize a refund after register a fulfillment with a failed status.", async () => {
      const payerRecordIds = await escrow.recordsOf(DUMMY_ADDRESS);
      FAILED_FULFILLMENT_RESULT.id = payerRecordIds[1];
      const r = await escrow.registerFulfillment(FAILED_FULFILLMENT_RESULT);
      expect(r).not.to.be.reverted;
      expect(r).to.emit(escrow, 'RefundAuthorized').withArgs(DUMMY_ADDRESS, ethers.parseUnits('101', 'wei'));
      const record = await escrow.record(payerRecordIds[1]);
      expect(record[10]).to.be.equal(0);
    });

    it("should allow manager to withdraw a refund.", async () => {
      const r = await escrow.withdrawRefund(DUMMY_ADDRESS);
      expect(r).not.to.be.reverted;
      expect(r).to.emit(escrow, 'RefundWithdrawn').withArgs(DUMMY_ADDRESS, ethers.parseUnits('101', 'wei'));
      const postBalance = await ethers.provider.getBalance(await escrow.getAddress());
      expect(postBalance).to.be.equal(101);
    });

    it("should not allow manager to withdraw a refund when there is none.", async () => {
      await expect(
        escrow.withdrawRefund(DUMMY_ADDRESS)
      ).to.be.revertedWith('Address is not allowed any refunds');
    });

    it("should not allow to register a fulfillment when it already was registered.", async () => {
      
    });
  });
});
