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
    const DUMMY_ADDRESS = "0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A";

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
            const feeAmount = ethers.parseUnits('0.1', 'ether');

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
            const service = await registry.getService(serviceID);

            // Verify the service details
            expect(service.serviceId).to.equal(serviceID);
            expect(service.contractAddress).to.be.a.properAddress;
            expect(service.fulfiller).to.equal(fulfiller.address);
            expect(service.validator).to.equal(validator.address);
            expect(service.feeAmount).to.equal(feeAmount);

            // Verify the ServiceAdded event
            expect(result).to.emit(manager, 'ServiceAdded').withArgs(serviceID, result[0], validator.address, fulfiller.address);
        });

        it('should revert if the service ID is invalid', async () => {
            const serviceID = 0;
            const feeAmount = ethers.parseUnits('0.1', 'ether');

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

        it('should revert if the service already exists.', async () => {
            const serviceID = 1;
            const feeAmount = ethers.parseUnits('0.1', 'ether');

            // Ensure the transaction reverts with an appropriate error message
            await expect(
                manager.setService(
                    serviceID,
                    beneficiary.address,
                    DUMMY_ADDRESS,
                    feeAmount,
                    fulfiller.address,
                    router.address
                )
            ).to.be.revertedWith('FulfillableRegistry: Service already exists');
        });

        // Add more test cases for different scenarios
    });
});
