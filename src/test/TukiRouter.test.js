const { ethers, upgrades } = require('hardhat');
const { expect, assert } = require('chai');
const BN = require('bn.js')

const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A"
const REVERT_ERROR_PREFIX = "Returned error: VM Exception while processing transaction:";


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
let registry;
let manager;

describe("TukyRouterV1", function () {

  before(async () => {
    [owner, beneficiary, fulfiller] = await ethers.getSigners();
    /**
     * deploy registry
     */
    const ServiceRegistry = await ethers.getContractFactory('FulfillableRegistry');
    const serviceRegistry = await upgrades.deployProxy(ServiceRegistry, []);
    await serviceRegistry.waitForDeployment();
    const registryAddress = await serviceRegistry.getAddress();
    registry = await ServiceRegistry.attach(registryAddress);
    /**
     * deploy router
     */
    const TukyRouterV1 = await ethers.getContractFactory('TukyRouterV1');
    routerContract = await upgrades.deployProxy(TukyRouterV1, [registryAddress]);
    await routerContract.waitForDeployment();
    v1 = TukyRouterV1.attach(await routerContract.getAddress());
    /**
     * deploy validator
     */
    const Validator = await ethers.deployContract('TwelveDigitsValidator');
    await Validator.waitForDeployment()
    regexValidator = Validator.attach(await Validator.getAddress())
    /**
     * deploy manager
     */
    const Manager = await ethers.getContractFactory('TukyFulfillmentManagerV1');
    const m = await upgrades.deployProxy(Manager, [registryAddress]);
    await m.waitForDeployment();
    manager = await Manager.attach(await m.getAddress());
    /**
     * set test service
     */
    const feeAmount = ethers.parseUnits('0.1', 'ether');
    manager.setService(
      1,
      await beneficiary.getAddress(),
      await Validator.getAddress(),
      feeAmount,
      await fulfiller.getAddress(),
      await routerContract.getAddress()
    );
  });

  describe("Upgradeability", async () => {
    it("should have transferred ownership to sender", async () => {
      assert.equal(await routerContract.owner(), await owner.getAddress());
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
        assert.equal(await v2.owner(), await owner.getAddress());
        await v2.pause({from: await beneficiary.getAddress()});
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
        assert.equal(await v2.owner(), await owner.getAddress());
        await v2.unpause({from: await beneficiary.getAddress()});
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
        const invalidOwner = await beneficiary.getAddress();
        const validOwner = await owner.getAddress();
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
        const newOwner = await beneficiary.getAddress();
        const oldOwner = await owner.getAddress();
        await v2.transferOwnership(newOwner);
        assert.equal(await v2.owner(), newOwner);
        const v2AsNewOwner = v2.connect(beneficiary)
        await v2AsNewOwner.transferOwnership(oldOwner);
        assert.equal(await v2.owner(), oldOwner);
    });
  });

  describe("Route to service", async () => {
    it("should fail when service id is not set in registry", async () => {
        const v2Signer1 = v2.connect(beneficiary)
        await expect(
          v2Signer1.requestService(2, DUMMY_FULFILLMENTREQUEST, {value: ethers.parseUnits("1000", "wei")})
        ).to.be.revertedWith('FulfillableRegistry: Service does not exist');
    });

    it("should fail for when amount is zero.", async () => {
        await expect(
          v2.requestService(1, DUMMY_VALID_FULFILLMENTREQUEST, {value: 0})
        ).to.be.revertedWith('Amount must be greater than zero');
    });

    it("should fail when the validator doesnt match", async () => {
      await expect(
        v2.requestService(1, DUMMY_FULFILLMENTREQUEST, {value: ethers.parseUnits("1000", "wei")})
      ).to.be.revertedWith('The service identifier failed to validate');
    });

    it("should fail with insufficient funds error", async () => {
        const service = await registry.getService(1);
        const feeAmount = new BN(service.feeAmount.toString());
        const weiAmount = new BN(DUMMY_VALID_FULFILLMENTREQUEST.weiAmount);
        total = weiAmount.add(feeAmount)
        try {
          await v2.requestService(1, DUMMY_VALID_FULFILLMENTREQUEST, { value: total.toString() })
        } catch (err) {
          assert.include(err.message, "sender doesn't have enough funds to send tx");
        };
    });

    it("should route to service escrow", async () => {
      const service = await registry.getService(1);
      DUMMY_VALID_FULFILLMENTREQUEST.weiAmount = ethers.parseUnits("1", "ether");
      const feeAmount = new BN(service.feeAmount.toString());
      const weiAmount = new BN(DUMMY_VALID_FULFILLMENTREQUEST.weiAmount);
      const tx = await v2.requestService(1, DUMMY_VALID_FULFILLMENTREQUEST, { value: weiAmount.add(feeAmount).toString() });
      const receipt = await tx.wait()
      expect(receipt).to.be.an('object').that.have.property('hash');
    });
  });
});
