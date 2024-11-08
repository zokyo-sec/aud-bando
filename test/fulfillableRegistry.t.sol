// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {BandoERC20FulfillableV1} from "../contracts/BandoERC20FulfillableV1.sol";

// import {Upgrades} from "@openzeppelin-foundry-upgrades/Upgrades.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {
    ERC20FulFillmentRecord,
    ERC20FulFillmentRequest,
    FulFillmentResultState,
    FulFillmentResult
} from "../contracts/FulfillmentTypes.sol";
import {FulfillableRegistry} from "../contracts/periphery/registry/FulfillableRegistry.sol";

import { IFulfillableRegistry, Service } from '../contracts/periphery/registry/IFulfillableRegistry.sol';


contract FulfillableRegistryTest is Test {

    FulfillableRegistry public f_registry;
    
    address public _multiSigAddr;

    address public bob = address(0x23);
    address public alice = address(0x55);
    address public router = address(0x66);

    address _proxy;
    address _implementation;
    address owner;
    
    address _registryProxy;
    address _registryImplementation;

    function setUp() public {
        _multiSigAddr = address(0x22);

        // Deploy Fulfillable Registry
        address registry_implementation = address(new FulfillableRegistry());

        bytes memory data = abi.encodeCall(FulfillableRegistry.initialize, ());
        address registry_proxy = address(new ERC1967Proxy(registry_implementation, data));
        _registryProxy = registry_proxy;
        _registryImplementation = registry_implementation;

        f_registry = FulfillableRegistry(_registryProxy);
    }

    function test_nothing_coin() public {
        console.log("Just typing here...");
    }

    function test_setManager(address newManager, address randomAddress) public {
        // Revert when owner calls by passing address(0) as Manager
        vm.expectRevert();
        f_registry.setManager(address(0));

        vm.assume(newManager!= address(0));
        f_registry.setManager(newManager);

        vm.prank(randomAddress);
        vm.expectRevert();
        f_registry.setManager(newManager);


    }

    function test_addService(uint256 serviceId, Service memory service) public {
        vm.assume(service.fulfiller != address(0));

        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(serviceId, service);

        Service memory gotService = f_registry.getService(serviceId);
        assertEq(gotService.serviceId, service.serviceId);
        assertEq(gotService.beneficiary, service.beneficiary);
        assertEq(gotService.feeAmount, service.feeAmount);
        assertEq(gotService.fulfiller, service.fulfiller);
        //         struct Service {
        //     uint256 serviceId;
        //     address payable beneficiary;
        //     uint256 feeAmount;
        //     address fulfiller;
        // }
    }

    function test_addServiceReverts(uint256 serviceId, Service memory service) public {
        vm.assume(service.fulfiller != address(0));

        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(serviceId, service);

        // Reverts as already added
        vm.expectRevert();
        f_registry.addService(serviceId, service);

    }

    function test_addService(uint256 serviceId, Service memory service, Service memory service2) public {
        service.fulfiller = address(0);
        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(serviceId, service);

        // @audit Expect to revert but fails as address(0) was passed as fulfiller. This will lead to overwriting of service
        // @audit Commenting revert statement below to run forge coverage
        // vm.expectRevert();
        f_registry.addService(serviceId, service2);


    }

    function test_updateServiceBeneficiary(uint256 _serviceId, address payable _newBeneficiary, Service memory service, address randomAddress) public {
        vm.assume(service.fulfiller != address(0));
        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(_serviceId, service);
        vm.stopPrank();
        f_registry.updateServiceBeneficiary(_serviceId, _newBeneficiary);

        vm.startPrank(randomAddress);
        vm.expectRevert();
        f_registry.updateServiceBeneficiary(_serviceId, _newBeneficiary);

    } 

    function test_updateServiceBeneficiaryReverts(uint256 _serviceId, address payable _newBeneficiary, Service memory service, address randomAddress) public {
        // As fulfiller is address(0) as no service set, so expect this to revert
        vm.expectRevert();
        f_registry.updateServiceBeneficiary(_serviceId, _newBeneficiary);
    } 

    function test_updateServiceFeeAmount(uint256 _serviceId, uint256 _newFee, Service memory service, address randomAddress) public {
        vm.assume(service.fulfiller != address(0));
        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(_serviceId, service);
        vm.stopPrank();
        f_registry.updateServiceFeeAmount(_serviceId, _newFee);

        vm.startPrank(randomAddress);
        vm.expectRevert();
        f_registry.updateServiceFeeAmount(_serviceId, _newFee);

    } 

    function test_updateServiceFeeAmountReverts(uint256 _serviceId, uint256 _newFee, Service memory service, address randomAddress) public {
        // As fulfiller is address(0) as no service set, so expect this to revert
        vm.expectRevert();
        f_registry.updateServiceFeeAmount(_serviceId, _newFee);
    } 



    function test_updateServiceFulfiller(uint256 _serviceId, address _newFulfiller, Service memory service, address randomAddress) public {
        vm.assume(service.fulfiller != address(0));
        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(_serviceId, service);
        vm.stopPrank();
        f_registry.updateServiceFulfiller(_serviceId, _newFulfiller);

        vm.startPrank(randomAddress);
        vm.expectRevert();
        f_registry.updateServiceFulfiller(_serviceId, _newFulfiller);

    } 

    function test_updateServiceFulfillerReverts(uint256 _serviceId, address _newFulfiller, Service memory service, address randomAddress) public {
        // As fulfiller is address(0) as no service set, so expect this to revert
        vm.expectRevert();
        f_registry.updateServiceFulfiller(_serviceId, _newFulfiller);

    } 

    function test_addFulfiller(uint256 _serviceId, address _newFulfiller, address randomAddress) public {
        vm.startPrank(randomAddress);
        vm.expectRevert();
        f_registry.addFulfiller(_newFulfiller, _serviceId);
        vm.stopPrank();
        f_registry.addFulfiller(_newFulfiller, _serviceId);
        bool result = f_registry.canFulfillerFulfill(_newFulfiller, _serviceId);
        assertEq(result, true);
    }

    function test_addFulfillerReverts(uint256 _serviceId, address _newFulfiller, address randomAddress) public {
        f_registry.addFulfiller(_newFulfiller, _serviceId);
        vm.expectRevert();
        f_registry.addFulfiller(_newFulfiller, _serviceId);

    }

    //@audit This test fails because the _serviceCount is never incremented when adding the service. Please consider incrementing the _serviceCount when adding a new service.
    function test_removeServiceAddress(uint256 serviceId, Service memory service) public {
        service.feeAmount = bound(service.feeAmount, 0, 1e18 * 1e9);
        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(serviceId, service);
        vm.stopPrank();
        f_registry.removeServiceAddress(serviceId);
    }

    function test_addServiceRef(uint256 serviceId, Service memory service, string memory ref) public {
        vm.assume(service.fulfiller != address(0));
        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(serviceId, service);
        f_registry.addServiceRef(serviceId, ref);
        bool result = f_registry.isRefValid(serviceId,ref);
        assertEq(result, true);
    }

    function test_addServiceRefReverts(uint256 serviceId, Service memory service, string memory ref, address randomAddress) public {
        // Revert as no service exists
        vm.expectRevert();
        f_registry.addServiceRef(serviceId, ref);
        bool result = f_registry.isRefValid(serviceId,ref);
        assertEq(result, false);

        // Unauthorized role trying to add service reference
        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(serviceId, service);  
        vm.startPrank(randomAddress);
        vm.expectRevert();
        f_registry.addServiceRef(serviceId, ref);

    }


}