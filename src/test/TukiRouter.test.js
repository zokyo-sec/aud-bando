const { ethers, upgrades } = require('hardhat');
const { expect, assert } = require('chai');
const BN = require('bn.js')

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
  weiAmount: 999,
  fiatAmount: 10,
  serviceRef: "01234XYZ" //invalid CFE 
}

/**
 * this should throw an "insufficient funds" error.
 */
const DUMMY_VALID_FULFILLMENTREQUEST = {
  payer: DUMMY_ADDRESS,
  weiAmount: ethers.parseUnits("11000", "ether"),
  fiatAmount: 101,
  serviceRef: "012345678912" //valid CFE
}

let routerContract;
let regexValidator;
let v2;
let signers;

describe("TukyRouterV1", function () {

  before(async () => {
    signers = await ethers.getSigners();
    const TukyRouterV1 = await ethers.getContractFactory('TukyRouterV1');
    const Validator = await ethers.deployContract('TwelveDigitsValidator');
    routerContract = await upgrades.deployProxy(TukyRouterV1, []);
    await routerContract.waitForDeployment();
    await Validator.waitForDeployment()
    regexValidator = Validator.attach(await Validator.getAddress())
    v1 = TukyRouterV1.attach(await routerContract.getAddress());
  });

  describe("Upgradeability", async () => {
    it("should have transferred ownership to sender", async () => {
      assert.equal(await routerContract.owner(), await signers[0].getAddress());
    });

    it("should have upgraded to new implementation", async () => {
        const UpgradeTester = await ethers.getContractFactory('RouterUpgradeTester')
        v2 = await upgrades.upgradeProxy(await routerContract.getAddress(), UpgradeTester);
        assert.equal(await v2.getAddress(), await routerContract.getAddress());
        v2 = UpgradeTester.attach(await routerContract.getAddress());
    });
  });

  describe("Pausability", async () => {
    it("should only allow an owner to pause the contract", async () => {
      try {
        assert.equal(await v2.owner(), await signers[0].getAddress());
        await v2.pause({from: await signers[1].getAddress()});
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.include(
          err.message,
          'from address mismatch',
        );
      }
      await v2.pause();
      assert.equal(await v2.paused(), true);
    });

    it("should only allow an owner to unpause the contract", async () => {
      try {
        assert.equal(await v2.owner(), await signers[0].getAddress());
        await v2.unpause({from: await signers[1].getAddress()});
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.include(
          err.message,
          'from address mismatch',
        );
      }
      await v2.unpause();
      assert.equal(await v2.paused(), false);
    });
  });

  describe("Ownability", async () => {
    it("should only allow an owner for test method", async () => {
      try {
        const invalidOwner = await signers[1].getAddress();
        const validOwner = await signers[0].getAddress();
        assert.notEqual(await v2.owner(), invalidOwner);
        assert.equal(await v2.owner(), validOwner)
        const response = await v2.isUpgrade({ from: invalidOwner });
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.include(
          err.message,
          'transaction from mismatch',
        );
      }
      assert.equal(await v2.isUpgrade(), true);
    });

    it("should allow owner to transfer ownership", async () => {
        const newOwner = await signers[1].getAddress();
        const oldOwner = await signers[0].getAddress();
        await v2.transferOwnership(newOwner);
        assert.equal(await v2.owner(), newOwner);
        const v2AsNewOwner = v2.connect(signers[1])
        await v2AsNewOwner.transferOwnership(oldOwner);
        assert.equal(await v2.owner(), oldOwner);
    });
  });

  describe("Route to service", async () => {

    it("should not allow a non-owner to set up a service", async () => {
      try {
        assert.notEqual(await v2.owner(), await signers[1].getAddress());
        const v2Invalid = v2.connect(signers[1])
        await v2Invalid.setService(1, DUMMY_ADDRESS, DUMMY_ADDRESS, 0, );
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.include(
          err.message,
          'OwnableUnauthorizedAccount'
        );
      }
    }); 

    it("should allow an owner to set up a service", async () => {
      const tx = await v2.setService(1, DUMMY_ADDRESS, await regexValidator.getAddress(), ethers.parseUnits('1', 'wei'));
      const receipt = await tx.wait()
      expect(tx).to.have.property("hash");
      expect(receipt.logs).to.be.an('array').that.has.lengthOf.greaterThanOrEqual(2);
      expect(receipt.logs[0]).to.have.property("fragment");
      expect(receipt.logs[1]).to.have.property("fragment");
      expect(receipt.logs[0].fragment).to.have.property("name");
      expect(receipt.logs[1].fragment).to.have.property("name");
      expect(receipt.logs[0].fragment).to.include({ name: 'OwnershipTransferred' });
      expect(receipt.logs[1].fragment).to.include({ name: 'ServiceAdded' });
    });

    it("should fail to add service when validator is not set or invalid.", async () => {
      try {
        await v2.setService(1, DUMMY_ADDRESS, null, 0);
        throw new Error("This should have thrown lines ago.");
      } catch (err) {
        assert.hasAnyKeys(err, ["code"]);
        assert.equal(err.code, "INVALID_ARGUMENT");
      }

      try {
        await v2.setService(1, DUMMY_ADDRESS, 10, 0);
        throw new Error("This should have thrown lines ago.");
      } catch(err) {
        assert.hasAnyKeys(err, ["code"]);
        assert.equal(err.code, "INVALID_ARGUMENT");
      }
    });

    it("should fail when service id is not set by owner", async () => {
      try {
        const v2Signer1 = v2.connect(signers[1])
        await v2Signer1.requestService(2, DUMMY_FULFILLMENTREQUEST, {value: ethers.parseUnits("1000", "wei")});
        throw new Error("This should have thrown lines ago.")
      } catch(err) {
        assert.include(
          err.message,
          'Service ID is not supported'
        );
      }
    });

    it("should fail for when amount is zero.", async () => {
      try {
        await v2.requestService(1, DUMMY_FULFILLMENTREQUEST, {value: 0});
        throw new Error("This should have thrown lines ago.")
      } catch(err) {
        assert.include(
          err.message,
          'Amount must be greater than zero'
        );
      }
    });

    it("should fail when the validator doesnt match", async () => {
      try {
        await v2.requestService(1, DUMMY_FULFILLMENTREQUEST, {value: ethers.parseUnits("1000", "wei")});
        throw new Error("This should have thrown lines ago.")
      } catch(err) {
        assert.include(
          err.message,  
          'The service identifier failed to validate'
        );
      }

      try {
        await v2.requestService(1, DUMMY_FULFILLMENTREQUEST, {value: ethers.parseUnits("1000", "wei")});
        throw new Error("This should have thrown lines ago.")
      } catch(err) {
        assert.include(
          err.message,
          'The service identifier failed to validate'
        );
      }
    });

    it("should fail with insufficient funds error", async () => {
      try {
        const fee = await v2.feeOf(1);
        const feeAmount = new BN(await fee.toString());
        const weiAmount = new BN(DUMMY_VALID_FULFILLMENTREQUEST.weiAmount);
        total = weiAmount.add(feeAmount)
        tx = await v2.requestService(1, DUMMY_VALID_FULFILLMENTREQUEST, { value: total.toString() });
        const r = await tx.wait()
      } catch(err) {
        assert.include(
          err.message,
          "sender doesn't have enough funds to send tx",
        );
      }
    });

    it("should send to escrow", async () => {
      const fee = await v2.feeOf(1);
      DUMMY_VALID_FULFILLMENTREQUEST.weiAmount = ethers.parseUnits("1", "ether");
      const feeAmount = new BN(await fee.toString());
      const weiAmount = new BN(DUMMY_VALID_FULFILLMENTREQUEST.weiAmount);
      const tx = await v2.requestService(1, DUMMY_VALID_FULFILLMENTREQUEST, { value: weiAmount.add(feeAmount).toString() });
      const receipt = await tx.wait()
      expect(receipt).to.be.an('object').that.have.property('hash');
    });
  });

  describe('Access Control', async () => {
    it("set an address as fulfiller", async () => {
      const fulfiller = await v2.setFulfiller(signers[1].getAddress());
      console.log(fulfiller);
    })
  });
});
