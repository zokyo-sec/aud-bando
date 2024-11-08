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
import { DemoToken } from '../contracts/test/TestERC20.sol';
import { IFulfillableRegistry, Service } from '../contracts/periphery/registry/IFulfillableRegistry.sol';
import { BandoFulfillmentManagerV1 } from '../contracts/BandoFulfillmentManagerV1.sol';

contract BandoERC20FulfillableV1Test is Test {

    BandoERC20FulfillableV1 public bandoERC20;
    FulfillableRegistry public f_registry;
    BandoFulfillmentManagerV1 public bandoManager;

    DemoToken public testERC20;
    address public _tokenAddress;
    
    address public _multiSigAddr;

    address public bob = address(0x23);
    address public alice = address(0x55);
    address public router = address(0x66);

    address _proxy;
    address _implementation;
    address owner;
    
    address _registryProxy;
    address _registryImplementation;

    address _managerProxy;
    address _managerImplementation;

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

        // Deploy a new token
        testERC20 = new DemoToken();
        testERC20.transfer(alice, 1);

        _tokenAddress = address(testERC20);
        console.log("Demo Token address:", _tokenAddress);

        // Deploy Fulfilment Manager
        address manager_implementation = address(new BandoFulfillmentManagerV1());

        data = abi.encodeCall(BandoFulfillmentManagerV1.initialize, ());
        address manager_proxy = address(new ERC1967Proxy(manager_implementation, data));
        _managerProxy = manager_proxy;
        _managerImplementation = manager_implementation;

        bandoManager = BandoFulfillmentManagerV1(_managerProxy);
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

    function test_registerFulfillment(ERC20FulFillmentRequest memory fulfillmentRequest, Service memory service) public {
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
        
        console.log("This is the TokenAmount from fulfillmentRequest: ", fulfillmentRequest.tokenAmount);
        
        // Deposit now after pranking router
        vm.startPrank(router);
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);

        // Call to registerFulfillment() will revert with "There is not enough balance to be released"
        vm.assume(service.feeAmount != 0);
        vm.startPrank(alice);
        vm.expectRevert();
        bandoERC20.registerFulfillment(service.serviceId, fulfillmentResult);
        vm.stopPrank();

        // Deposit again to ensure sufficient balance
        vm.startPrank(router);
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);


        // Now call registerFulfillment
        vm.startPrank(alice);
        bandoERC20.registerFulfillment(service.serviceId, fulfillmentResult);
        vm.stopPrank();

        // Now call registerFulfillment with STATUS FAILED
         _id = 2; //id will always be 1 for the 1st record
        fulfillmentResult = FulFillmentResult({
            id: _id,
            externalID: "",
            receiptURI: "",
            status: FulFillmentResultState.FAILED
        });

        vm.startPrank(router);
        console.log("This is the TokenAmount from fulfillmentRequest: ", fulfillmentRequest.tokenAmount);
        
        // Calling twice to ensure sufficient deposit amount
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);


        vm.startPrank(alice);
        bandoERC20.registerFulfillment(service.serviceId, fulfillmentResult);
        vm.stopPrank();

        // Now call registerFulfillment with STATUS PENDING
        _id = 3; //id will always be 1 for the 1st record
        fulfillmentResult = FulFillmentResult({
            id: _id,
            externalID: "",
            receiptURI: "",
            status: FulFillmentResultState.PENDING
        });

        vm.startPrank(router);
        console.log("This is the TokenAmount from fulfillmentRequest: ", fulfillmentRequest.tokenAmount);
        
        // Calling twice to ensure sufficient deposit amount
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);


        vm.startPrank(alice);
        vm.expectRevert();
        bandoERC20.registerFulfillment(service.serviceId, fulfillmentResult);
        vm.stopPrank();

    }

    function test_withdrawRefund(ERC20FulFillmentRequest memory fulfillmentRequest, Service memory service) public {
        vm.assume(fulfillmentRequest.payer != address(0));
        vm.assume(service.beneficiary != address(0));
        uint256 _id = 1; //id will always be 1 for the 1st record
        FulFillmentResult memory fulfillmentResult = FulFillmentResult({
            id: _id,
            externalID: "",
            receiptURI: "",
            status: FulFillmentResultState.FAILED
        });
        fulfillmentRequest.token = _tokenAddress;
        // Bounding and limiting values to prevent Overflow errors
        vm.assume(service.fulfiller != address(0));
        service.serviceId = bound(service.serviceId, 1, 1000000);
        service.feeAmount = bound(service.feeAmount, 0, 1e18);
        fulfillmentRequest.tokenAmount = bound(fulfillmentRequest.tokenAmount, service.feeAmount + 1, service.feeAmount + 10e18);
        console.log("FeeAmount is:", service.feeAmount);

        bandoERC20.setManager(alice); // only setting manager of bandoerc20 as alice
        bandoERC20.setRouter(router);
        bandoERC20.setFulfillableRegistry(_registryProxy);

        // Adding Fulfillment record now by calling depositERC20()
        // bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);
        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(service.serviceId, service);
        vm.stopPrank();
        
        console.log("This is the TokenAmount from fulfillmentRequest: ", fulfillmentRequest.tokenAmount);
        
        // Deposit now after pranking router
        vm.startPrank(router);
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);

        // Deposit again to ensure sufficient balance
        vm.startPrank(router);
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);
        vm.stopPrank();

        // Now call registerFulfillment and refund is issues due to FAILED status
        testERC20.transfer(address(bandoERC20), 1000*10**18);
        vm.startPrank(alice);
        bandoERC20.registerFulfillment(service.serviceId, fulfillmentResult);

        // Revert if non manager calls
        vm.startPrank(bob);
        vm.expectRevert();
        bandoERC20.withdrawERC20Refund(service.serviceId, _tokenAddress, fulfillmentRequest.payer); 

        // Also revert if refundee is not authorized
        vm.startPrank(alice);
        vm.expectRevert();
        bandoERC20.withdrawERC20Refund(service.serviceId, _tokenAddress, alice);  

        // Manager now calls withdrawERC20Refund()
        vm.startPrank(alice);
        bandoERC20.withdrawERC20Refund(service.serviceId, _tokenAddress, fulfillmentRequest.payer); 
    }

    function test_beneficiaryWithdraw(ERC20FulFillmentRequest memory fulfillmentRequest, Service memory service) public 
    {
        vm.assume(fulfillmentRequest.payer != address(0));
        vm.assume(service.beneficiary != address(0));
        uint256 _id = 1; //id will always be 1 for the 1st record
        FulFillmentResult memory fulfillmentResult = FulFillmentResult({
            id: _id,
            externalID: "",
            receiptURI: "",
            status: FulFillmentResultState.SUCCESS
        });
        fulfillmentRequest.token = _tokenAddress;
        // Bounding and limiting values to prevent Overflow errors
        vm.assume(service.fulfiller != address(0));
        service.serviceId = bound(service.serviceId, 1, 1000000);
        service.feeAmount = bound(service.feeAmount, 0, 1e18);
        fulfillmentRequest.tokenAmount = bound(fulfillmentRequest.tokenAmount, service.feeAmount + 1, service.feeAmount + 10e18);
        console.log("FeeAmount is:", service.feeAmount);

        bandoERC20.setManager(alice); // only setting manager of bandoerc20 as alice
        bandoERC20.setRouter(router);
        bandoERC20.setFulfillableRegistry(_registryProxy);

        // Adding Fulfillment record now by calling depositERC20()
        // bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);
        f_registry.setManager(alice);
        vm.startPrank(alice);
        f_registry.addService(service.serviceId, service);
        vm.stopPrank();
        
        console.log("This is the TokenAmount from fulfillmentRequest: ", fulfillmentRequest.tokenAmount);
        
        // Deposit now after pranking router
        vm.startPrank(router);
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);

        // Deposit again to ensure sufficient balance
        vm.startPrank(router);
        bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);
        vm.stopPrank();

        // Now call registerFulfillment and refund is issues due to FAILED status
        // testERC20.transfer(address(bandoERC20), 1000*10**18);
        vm.startPrank(alice);
        bandoERC20.registerFulfillment(service.serviceId, fulfillmentResult);
        vm.stopPrank();
        testERC20.transfer(address(bandoERC20), 1000*10**18);
        vm.startPrank(alice);
        bandoERC20.beneficiaryWithdraw(service.serviceId, fulfillmentRequest.token);
    }

//////////////////////////////////////// FULFILLMENT MANAGER TESTS /////////////////////////////////////////


    function test_setterFunctions(address payable _serviceRegistry, address payable _escrow, address payable _erc20Escrow) public 
    {
        vm.assume(_serviceRegistry != address(0));
        vm.assume(_escrow != address(0));
        vm.assume(_erc20Escrow != address(0));

        bandoManager.setServiceRegistry(_serviceRegistry);
        bandoManager.setEscrow(_escrow);
        bandoManager.setERC20Escrow(_erc20Escrow);
    }
    function test_setService(
        uint256 _serviceID,
        uint256 _feeAmount,
        address _fulfiller,
        address payable beneficiary,
        string memory _serviceRef
    ) public {
        bandoManager.setServiceRegistry(address(f_registry));
        f_registry.setManager(address(bandoManager));
        vm.assume(_serviceID != 0);
        vm.assume(_fulfiller != address(0));
        vm.assume(beneficiary != address(0));
    
        bandoManager.setService( _serviceID, _feeAmount, _fulfiller, beneficiary);
        bandoManager.setServiceRef(_serviceID, _serviceRef);

    } 

    function test_registerFulfillmentViaManager(uint256 serviceID, 
        uint256 _serviceID,
        uint256 _feeAmount,
        address _fulfiller,
        address payable beneficiary,
        string memory _serviceRef ,
        ERC20FulFillmentRequest memory fulfillmentRequest) public {
            vm.assume(_fulfiller != address(0));

            // Bounding values
            _serviceID = bound(_serviceID, 1, 1000000);
            _feeAmount = bound(_feeAmount, 0, 1e18);
            fulfillmentRequest.tokenAmount = bound(fulfillmentRequest.tokenAmount, _feeAmount + 1, _feeAmount + 10e18);

            bandoManager.setServiceRegistry(address(f_registry));
            f_registry.setManager(address(bandoManager));
            vm.assume(_serviceID != 0);
            vm.assume(_fulfiller != address(0));
            vm.assume(beneficiary != address(0));
        
            bandoManager.setService( _serviceID, _feeAmount, _fulfiller, beneficiary);
            bandoManager.setServiceRef(_serviceID, _serviceRef);
            uint256 _id = 1;
            FulFillmentResult memory fulfillmentResult = FulFillmentResult({
                id: _id,
                externalID: "",
                receiptURI: "",
                status: FulFillmentResultState.SUCCESS
            });

            bandoManager.setEscrow(payable(address(bandoERC20)));
            bandoERC20.setManager(address(bandoManager));
            bandoERC20.setRouter(router);
            bandoERC20.setFulfillableRegistry(_registryProxy);


            // Deposit now after pranking router
            vm.startPrank(router);
            vm.assume(fulfillmentRequest.tokenAmount > 0);
            vm.assume(fulfillmentRequest.tokenAmount < type(uint256).max);
            vm.assume(fulfillmentRequest.fiatAmount < type(uint256).max/2);
            bandoERC20.depositERC20(_serviceID, fulfillmentRequest);
            bandoERC20.depositERC20(_serviceID, fulfillmentRequest);
            vm.stopPrank();

            bandoManager.registerFulfillment(_serviceID, fulfillmentResult);

    }

        function test_registerFulfillmentViaManagerWithRefund(uint256 serviceID, 
        uint256 _serviceID,
        uint256 _feeAmount,
        address _fulfiller,
        address payable beneficiary,
        string memory _serviceRef ,
        ERC20FulFillmentRequest memory fulfillmentRequest) public {
            vm.assume(_fulfiller != address(0));

            // Bounding values
            _serviceID = bound(_serviceID, 1, 1000000);
            _feeAmount = bound(_feeAmount, 0, 1e18);
            fulfillmentRequest.tokenAmount = bound(fulfillmentRequest.tokenAmount, _feeAmount + 1, _feeAmount + 10e18);
            fulfillmentRequest.token = _tokenAddress;
            vm.assume(fulfillmentRequest.tokenAmount > 0);
            vm.assume(fulfillmentRequest.tokenAmount < type(uint256).max);
            vm.assume(fulfillmentRequest.fiatAmount < type(uint256).max/2);

            bandoManager.setServiceRegistry(address(f_registry));
            f_registry.setManager(address(bandoManager));
            vm.assume(_serviceID != 0);
            vm.assume(_fulfiller != address(0));
            vm.assume(beneficiary != address(0));
        
            bandoManager.setService( _serviceID, _feeAmount, _fulfiller, beneficiary);
            bandoManager.setServiceRef(_serviceID, _serviceRef);
            uint256 _id = 1;
            FulFillmentResult memory fulfillmentResult = FulFillmentResult({
                id: _id,
                externalID: "",
                receiptURI: "",
                status: FulFillmentResultState.FAILED
            });

            bandoManager.setEscrow(payable(address(bandoERC20)));
            bandoERC20.setManager(address(bandoManager));
            bandoERC20.setRouter(router);
            bandoERC20.setFulfillableRegistry(_registryProxy);

            // Deposit now after pranking router
            vm.startPrank(router);

            bandoERC20.depositERC20(_serviceID, fulfillmentRequest);
            bandoERC20.depositERC20(_serviceID, fulfillmentRequest);
            vm.stopPrank();
            
            testERC20.transfer(address(bandoERC20), 1000*10**18);
            
            bandoManager.registerFulfillment(_serviceID, fulfillmentResult);
            bandoManager.setERC20Escrow(payable(address(bandoERC20)));
            bandoManager.withdrawERC20Refund(_serviceID, _tokenAddress, fulfillmentRequest.payer);
    }

//     function test_registerFulfillmentRevertsOnOverflows(ERC20FulFillmentRequest memory fulfillmentRequest, Service memory service) public {
//         uint256 _id = 1; //id will always be 1 for the 1st record
//         FulFillmentResult memory fulfillmentResult = FulFillmentResult({
//             id: _id,
//             externalID: "",
//             receiptURI: "",
//             status: FulFillmentResultState.SUCCESS
//         });

//         // Revert when non-manager address calling the function
//         vm.prank(bob);
//         vm.expectRevert();
//         bandoERC20.registerFulfillment(service.serviceId, fulfillmentResult);
        
//         // Bounding and limiting values to prevent Overflow errors
//         vm.assume(service.fulfiller != address(0));
//         service.serviceId = bound(service.serviceId, 1, 1000000);
//         service.feeAmount = 100e18;
        
//         // Reverts with "Overflow while adding deposits"
//         // vm.expectRevert();
//         fulfillmentRequest.tokenAmount = service.feeAmount + 100000000000000000000000000000000000000000000000000000000000e18;
//         console.log("FeeAmount is:", service.feeAmount);

//         bandoERC20.setManager(alice); // only setting manager of bandoerc20 as alice
//         bandoERC20.setRouter(router);
//         bandoERC20.setFulfillableRegistry(_registryProxy);


//         // Adding Fulfillment record now by calling depositERC20()
//         // bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);
//         f_registry.setManager(alice);
//         vm.startPrank(alice);
//         f_registry.addService(service.serviceId, service);
//         vm.stopPrank();
        
//         console.log("This is the TokenAmount from fulfillmentRequest: ", fulfillmentRequest.tokenAmount);
        
//         // Deposit now after pranking router
//         vm.startPrank(router);
//         bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);

//         // Deposit again to ensure sufficient balance
//         vm.startPrank(router);
//         bandoERC20.depositERC20(service.serviceId, fulfillmentRequest);

//         // Now call registerFulfillment
//         vm.startPrank(alice);
//         bandoERC20.registerFulfillment(service.serviceId, fulfillmentResult);
//         vm.stopPrank();
// }


}