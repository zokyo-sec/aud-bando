const { expect } = require('chai');
const { ethers, upgrades } = require('hardhat');

describe('TukyFulfillmentManagerV1', () => {
    let owner;
    let validator;
    let fulfiller;
    let beneficiary;
    let router;
    let registry;
    let manager;

    before(async () => {
        [owner, validator, fulfiller, beneficiary, router] = await ethers.getSigners();
        //deploy registry
        const ServiceRegistry = await ethers.getContractFactory('FulfillableRegistry');
        const serviceRegistry = await upgrades.deployProxy(ServiceRegistry, []);
        await serviceRegistry.waitForDeployment();
        const registryAddress = await serviceRegistry.getAddress();
        registry = await ServiceRegistry.attach(registryAddress);
        // Deploy the TukyFulfillmentManagerV1 contract
        const TukyFulfillmentManager = await ethers.getContractFactory('TukyFulfillmentManagerV1');
        const tukyFulfillmentManager = await upgrades.deployProxy(TukyFulfillmentManager, [registryAddress]);
        await tukyFulfillmentManager.waitForDeployment();
        manager = await TukyFulfillmentManager.attach(await tukyFulfillmentManager.getAddress());
    });

    describe('setService', () => {
        it('should set up a service', async () => {
            const serviceID = 1;
            const feeAmount = ethers.utils.parseEther('0.1');

            // Set up the service
            const result = await manager.setService(
                serviceID,
                beneficiary.address,
                validator.address,
                feeAmount,
                fulfiller.address,
                router.address
            );

            // Retrieve the service details from the registry
            const service = await serviceRegistry.getService(serviceID);

            // Verify the service details
            expect(service.serviceId).to.equal(serviceID);
            expect(service.contractAddress).to.equal(result[0]);
            expect(service.fulfiller).to.equal(fulfiller.address);
            expect(service.validator).to.equal(validator.address);
            expect(service.feeAmount).to.equal(feeAmount);

            // Verify the ServiceAdded event
            expect(result).to.emit(manager, 'ServiceAdded').withArgs(serviceID, result[0], validator.address, fulfiller.address);
        });

        it('should revert if the service ID is invalid', async () => {
            const serviceID = 0;
            const feeAmount = ethers.utils.parseEther('0.1');

            // Ensure the transaction reverts with an appropriate error message
            await expect(
                manager.setService(
                    serviceID,
                    beneficiary.address,
                    validator.address,
                    feeAmount,
                    fulfiller.address,
                    router.address
                )
            ).to.be.revertedWith('Service ID is invalid');
        });

        it('should revert if the validator address is not provided', async () => {
            const serviceID = 1;
            const feeAmount = ethers.utils.parseEther('0.1');

            // Ensure the transaction reverts with an appropriate error message
            await expect(
                manager.setService(
                    serviceID,
                    beneficiary.address,
                    ethers.constants.AddressZero,
                    feeAmount,
                    fulfiller.address,
                    router.address
                )
            ).to.be.revertedWith('Validator address is required.');
        });

        // Add more test cases for different scenarios
    });

    describe('withdrawRefund', () => {
        it('should allow the fulfiller to withdraw a refund', async () => {
            const serviceID = 1;
            const refundee = fulfiller.address;

            // Set up the service
            await manager.setService(
                serviceID,
                beneficiary.address,
                validator.address,
                ethers.utils.parseEther('0.1'),
                fulfiller.address,
                router.address
            );

            // Call the withdrawRefund function
            await manager.withdrawRefund(serviceID, refundee);

            // Verify that the refund was successfully withdrawn
            // Add your verification logic here
        });

        it('should revert if called by a non-fulfiller', async () => {
            const serviceID = 1;
            const refundee = fulfiller.address;

            // Set up the service
            await manager.setService(
                serviceID,
                beneficiary.address,
                validator.address,
                ethers.utils.parseEther('0.1'),
                fulfiller.address,
                router.address
            );

            // Ensure the transaction reverts with an appropriate error message
            await expect(
                manager.connect(owner).withdrawRefund(serviceID, refundee)
            ).to.be.revertedWith('Only the fulfiller can withdraw the refund');
        });

        // Add more test cases for different scenarios
    });

    describe('registerFulfillment', () => {
        it('should allow the fulfiller to register a fulfillment', async () => {
            const serviceID = 1;
            const fulfillment = 'Fulfillment result';

            // Set up the service
            await manager.setService(
                serviceID,
                beneficiary.address,
                validator.address,
                ethers.utils.parseEther('0.1'),
                fulfiller.address,
                router.address
            );

            // Call the registerFulfillment function
            await manager.registerFulfillment(serviceID, fulfillment);

            // Verify that the fulfillment was successfully registered
            // Add your verification logic here
        });

        it('should revert if called by a non-fulfiller', async () => {
            const serviceID = 1;
            const fulfillment = 'Fulfillment result';

            // Set up the service
            await manager.setService(
                serviceID,
                beneficiary.address,
                validator.address,
                ethers.utils.parseEther('0.1'),
                fulfiller.address,
                router.address
            );

            // Ensure the transaction reverts with an appropriate error message
            await expect(
                manager.connect(owner).registerFulfillment(serviceID, fulfillment)
            ).to.be.revertedWith('Only the fulfiller can register a fulfillment');
        });

        // Add more test cases for different scenarios
    });

    // Add more test cases for other functions

});
