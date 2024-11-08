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


contract BandoERC20FulfillableV1Test is Test {

    BandoERC20FulfillableV1 public bandoERC20;
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
        address implementation = address(new BandoERC20FulfillableV1());

        bytes memory data = abi.encodeCall(BandoERC20FulfillableV1.initialize, ());
        address proxy = address(new ERC1967Proxy(implementation, data));
        _proxy = proxy;
        _implementation = implementation;
        owner = _multiSigAddr;

        bandoERC20 = BandoERC20FulfillableV1(proxy);
        

        // Deploy Fulfillable Registry
        address registry_implementation = address(new FulfillableRegistry());

        data = abi.encodeCall(FulfillableRegistry.initialize, ());
        address registry_proxy = address(new ERC1967Proxy(registry_implementation, data));
        _registryProxy = registry_proxy;
        _registryImplementation = registry_implementation;

        f_registry = FulfillableRegistry(_registryProxy);


    }

    function test_nothing_coin() public {
        console.log("Just typing here...");
    }

    function test_setManager(address newManager) public {
        vm.assume(newManager!= address(0));
        bandoERC20.setManager(newManager);

        vm.prank(alice);
        vm.expectRevert();
        bandoERC20.setManager(newManager);
        
    }

    function test_setRouter(address newRouter) public {
        vm.assume(newRouter!= address(0));
        bandoERC20.setRouter(newRouter);
        vm.prank(alice);
        vm.expectRevert();
        bandoERC20.setRouter(newRouter);
    }

    function test_setFulfillableRegistry(address newRouter) public {
        vm.assume(newRouter!= address(0));
        bandoERC20.setRouter(newRouter);
        vm.prank(alice);
        vm.expectRevert();
        bandoERC20.setRouter(newRouter);
    }

    function test_depositERC20(uint256 serviceID, ERC20FulFillmentRequest memory fulfillmentRequest, Service memory service) public {
        vm.assume(service.fulfiller != address(0));

        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(serviceID, service);
        vm.stopPrank();


        uint256 probably_nothing = serviceID;
        bandoERC20.setRouter(router);
        bandoERC20.setFulfillableRegistry(_registryProxy);
        

        vm.prank(router);
        vm.assume(fulfillmentRequest.tokenAmount > 0);
        vm.assume(fulfillmentRequest.tokenAmount < type(uint256).max);
        vm.assume(fulfillmentRequest.fiatAmount < type(uint256).max/2);
        bandoERC20.depositERC20(serviceID, fulfillmentRequest);
    }

    function test_depositERC20Reverts(uint256 serviceID, ERC20FulFillmentRequest memory fulfillmentRequest, Service memory service) public {
        vm.assume(service.fulfiller != address(0));

        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(serviceID, service);
        vm.stopPrank();

        bandoERC20.setRouter(router);
        bandoERC20.setFulfillableRegistry(_registryProxy);
        

        vm.prank(alice);
        vm.assume(fulfillmentRequest.tokenAmount > 0);
        vm.assume(fulfillmentRequest.tokenAmount < type(uint256).max);
        vm.assume(fulfillmentRequest.fiatAmount < type(uint256).max/2);
        
        // Reverts as called by non-router address
        vm.expectRevert();
        bandoERC20.depositERC20(serviceID, fulfillmentRequest);
    }

    function test_registerFulfillment(uint256 serviceID, ERC20FulFillmentRequest memory fulfillmentRequest, Service memory service) public {
        vm.assume(service.fulfiller != address(0));

        f_registry.setManager(alice);
        // vm.startPrank(alice);
    }

    function test_registerFulfillmentReverts(ERC20FulFillmentRequest memory fulfillmentRequest, Service memory service) public {
        uint256 _id = 1; //id will always be 1 for the 1st record
        FulFillmentResult memory fulfillmentResult = FulFillmentResult({
            id: _id,
            externalID: "",
            receiptURI: "",
            status: FulFillmentResultState.SUCCESS
        });

        // Revert when non-manager address calling the function
        vm.prank(bob);
        vm.expectRevert();
        bandoERC20.registerFulfillment(service.serviceId, fulfillmentResult);
        
        // Bounding and limiting values to prevent Overflow errors
        vm.assume(service.fulfiller != address(0));
        service.serviceId = bound(service.serviceId, 1, 1000000);
        service.feeAmount = bound(service.feeAmount, 0, 100e18);
        fulfillmentRequest.tokenAmount = bound(fulfillmentRequest.tokenAmount, service.feeAmount + 1, service.feeAmount + 100e18);
        console.log("FeeAmount is:", service.feeAmount);

        // f_registry.setManager(alice);
        bandoERC20.setManager(alice); // only setting manager of bandoerc20 as alice


        bandoERC20.setRouter(router);
        bandoERC20.setFulfillableRegistry(_registryProxy);

        vm.startPrank(alice);
        // Reverts with error "Fulfillment record does not exist"
        vm.expectRevert();
        bandoERC20.registerFulfillment(service.serviceId, fulfillmentResult);
        vm.stopPrank();

        // Adding Fulfillment record now by calling depositERC20()
        // bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);
        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(service.serviceId, service);
        vm.stopPrank();


        bandoERC20.setFulfillableRegistry(_registryProxy);
        

        vm.startPrank(router);
    
        // vm.assume(fulfillmentRequest.tokenAmount  >  service.feeAmount)
        console.log("This is the TokenAmount from fulfillmentRequest: ", fulfillmentRequest.tokenAmount);

        // Calling twice to ensure sufficient deposit amount
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);


        // Now call registerFulfillment
        vm.startPrank(alice);
        bandoERC20.registerFulfillment(service.serviceId, fulfillmentResult);
        vm.stopPrank();

        
    }



}