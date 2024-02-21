const { expect, assert } = require("chai");
const { ethers, upgrades } = require("hardhat");
const { v4: uuidv4 } = require('uuid');

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A"

const DUMMY_FULFILLMENTREQUEST = {
  payer: DUMMY_ADDRESS,
  tokenAmount: 100,
  fiatAmount: 10,
  serviceRef: "01234XYZ",
  token: ''
}
 
const SUCCESS_FULFILLMENT_RESULT = {
  status: 1,
  externalID: uuidv4(),
  receiptURI: 'https://test.com',
  id: null,
}

const INVALID_FULFILLMENT_RESULT = {
  status: 3,
  externalID: uuidv4(),
  receiptURI: 'https://test.com',
  id: null,
}

const FAILED_FULFILLMENT_RESULT = {
  status: 0,
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
let erc20Test;

describe("TukiERC20FulfillableV1", () => {
  
  before(async () => {
    [owner, beneficiary, fulfiller, router] = await ethers.getSigners();
    erc20Test = await ethers.deployContract('DemoToken');
    await erc20Test.waitForDeployment();
    fulfillerContract = await ethers.deployContract('TukyERC20FulfillableV1', [
      beneficiary, 1, router, fulfiller
    ]);
    await erc20Test.approve(await fulfillerContract.getAddress(), ethers.parseUnits('1000000', 18));
    await fulfillerContract.waitForDeployment();
    escrow = fulfillerContract.attach(await fulfillerContract.getAddress())
    taddr = await erc20Test.getAddress();
    DUMMY_FULFILLMENTREQUEST.token = taddr;
    SUCCESS_FULFILLMENT_RESULT.token = taddr;
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
        escrow.depositERC20(DUMMY_FULFILLMENTREQUEST)
      ).to.be.revertedWith('Caller is not the router');
    });

    it("should allow a payable deposit coming from the router.", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = await owner.getAddress();
      DUMMY_FULFILLMENTREQUEST.tokenAmount = ethers.parseUnits('1000', 18);
      const fromRouter = await escrow.connect(router);
      const response = await fromRouter.depositERC20(DUMMY_FULFILLMENTREQUEST);
      const BNresponse = await fulfillerContract.depositsOf(DUMMY_FULFILLMENTREQUEST.token, DUMMY_FULFILLMENTREQUEST.payer);
      assert.equal(BNresponse.toString(), "1000000000000000000000");
      const erc20PostBalance = await erc20Test.balanceOf(await escrow.getAddress());
      expect(erc20PostBalance).to.be.equal("1000000000000000000000");

      const response2 = await fromRouter.depositERC20(DUMMY_FULFILLMENTREQUEST);
      const BNresponse2 = await fulfillerContract.depositsOf(DUMMY_FULFILLMENTREQUEST.token, DUMMY_FULFILLMENTREQUEST.payer);
      assert.equal(BNresponse2.toString(), "2000000000000000000000");
      const erc20PostBalance2 = await erc20Test.balanceOf(await escrow.getAddress());
      expect(erc20PostBalance2).to.be.equal("2000000000000000000000");
    });

    it("should emit a DepositReceived event", async () => {
      DUMMY_FULFILLMENTREQUEST.payer = owner;
      DUMMY_FULFILLMENTREQUEST.tokenAmount = ethers.parseUnits("100", 18);
      const fromRouter = await escrow.connect(router);
      await expect(
        fromRouter.depositERC20(DUMMY_FULFILLMENTREQUEST)
      ).to.emit(escrow, "DepositReceived")
    });

    it("should persist unique fulfillment records on the blockchain", async () => {
      const payerRecordIds = await escrow.recordsOf(owner);
      const record1 = await escrow.record(payerRecordIds[0]);
      expect(record1[0]).to.be.equal(1); //record ID
      expect(record1[2]).to.be.equal(await fulfiller.getAddress()); //fulfiller
      expect(record1[3]).to.be.equal(await erc20Test.getAddress()); //token
      expect(record1[5]).to.be.equal(owner); //payer address
      expect(record1[11]).to.be.equal(2); //status. 2 = PENDING
    });
  });

  describe("Register Fulfillment Specs", () => {
    it("should only allow to register a fulfillment via the manager", async () => {
      const fromRouter = await escrow.connect(router);
      const payerRecordIds = await fromRouter.recordsOf(owner);
      SUCCESS_FULFILLMENT_RESULT.id = payerRecordIds[0];
      await expect(
        fromRouter.registerFulfillment(SUCCESS_FULFILLMENT_RESULT)
      ).to.be.revertedWith('Caller is not the manager');
      await expect(
        escrow.registerFulfillment(SUCCESS_FULFILLMENT_RESULT)
      ).not.to.be.reverted;
      const record = await escrow.record(payerRecordIds[0]);
      expect(record[11]).to.be.equal(1);
    });

    it("should not allow to register a fulfillment with an invalid status.", async () => {
      const payerRecordIds = await escrow.recordsOf(owner);
      INVALID_FULFILLMENT_RESULT.id = payerRecordIds[1];
      await expect(
        escrow.registerFulfillment(INVALID_FULFILLMENT_RESULT)
      ).to.be.reverted;
      const record = await escrow.record(payerRecordIds[1]);
      expect(record[11]).to.be.equal(2);
    });

    it("should authorize a refund after register a fulfillment with a failed status.", async () => {
      const payerRecordIds = await escrow.recordsOf(owner);
      FAILED_FULFILLMENT_RESULT.id = payerRecordIds[1];
      const r = escrow.registerFulfillment(FAILED_FULFILLMENT_RESULT);
      await expect(r).not.to.be.reverted;
      await expect(r).to.emit(escrow, 'RefundAuthorized').withArgs(owner, ethers.parseUnits('1000', 18));
      const record = await escrow.record(payerRecordIds[1]);
      expect(record[11]).to.be.equal(0);
    });

    it("should allow manager to withdraw a refund.", async () => {
      const r = escrow.withdrawERC20Refund(erc20Test, owner);
      await expect(r).not.to.be.reverted;
      await expect(r).to.emit(escrow, 'RefundWithdrawn').withArgs(erc20Test, owner, ethers.parseUnits('1000', 18));
    });

    it("should not allow manager to withdraw a refund when there is none.", async () => {
      await expect(
        escrow.withdrawERC20Refund(erc20Test, owner)
      ).to.be.revertedWith('Address is not allowed any refunds');
    });

    it("should not allow to register a fulfillment when it already was registered.", async () => {
      const payerRecordIds = await escrow.recordsOf(owner);
      const record1 = await escrow.record(payerRecordIds[0]);
      const extID = record1[3];
      SUCCESS_FULFILLMENT_RESULT.id = payerRecordIds[0];
      await expect(
        escrow.registerFulfillment(SUCCESS_FULFILLMENT_RESULT)
      ).to.be.revertedWith('Fulfillment already registered');
    });
  });
});
