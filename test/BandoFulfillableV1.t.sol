// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/BandoFulfillableV1.sol";
import "../contracts/periphery/registry/FulfillableRegistry.sol";
import "../contracts/FulfillmentTypes.sol";

contract BandoFulfillableV1Test is Test {
    BandoFulfillableV1 public escrow;
    FulfillableRegistry public registry;
    address public owner;
    address public beneficiary;
    address public fulfiller;
    address public router;
    address public manager;
    address public managerEOA;
    address constant DUMMY_ADDRESS =
        address(0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A);

    FulFillmentRequest DUMMY_FULFILLMENTREQUEST;
    FulFillmentResult SUCCESS_FULFILLMENT_RESULT;
    FulFillmentResult INVALID_FULFILLMENT_RESULT;
    FulFillmentResult FAILED_FULFILLMENT_RESULT;

    event RefundAuthorized(address indexed payee, uint256 weiAmount);
    event RefundWithdrawn(address indexed payee, uint256 weiAmount);

    function setUp() public {
        owner = address(this);
        beneficiary = payable(address(0x1));
        fulfiller = address(0x2);
        router = address(0x3);
        manager = address(0x4);

        registry = new FulfillableRegistry();
        registry.initialize();
        registry.setManager(address(this));

        escrow = new BandoFulfillableV1();
        escrow.initialize();
        escrow.setManager(manager);
        escrow.setRouter(router);
        escrow.setFulfillableRegistry(address(registry));

        Service memory newService = Service({
            serviceId: 1,
            beneficiary: payable(beneficiary),
            feeAmount: 0,
            fulfiller: fulfiller
        });
        registry.addService(1, newService);

        DUMMY_FULFILLMENTREQUEST = FulFillmentRequest({
            payer: DUMMY_ADDRESS,
            weiAmount: 101,
            fiatAmount: 10,
            serviceRef: "01234XYZ"
        });

        SUCCESS_FULFILLMENT_RESULT = FulFillmentResult({
            status: FulFillmentResultState.SUCCESS,
            id: 0, // Will be set in the test
            externalID: "success-external-id",
            receiptURI: "https://success.com"
        });

        INVALID_FULFILLMENT_RESULT = FulFillmentResult({
            status: FulFillmentResultState.PENDING, // Invalid status
            id: 0,
            externalID: "invalid-external-id",
            receiptURI: "https://invalid.com"
        });

        FAILED_FULFILLMENT_RESULT = FulFillmentResult({
            status: FulFillmentResultState.FAILED,
            id: 0,
            externalID: "failed-external-id",
            receiptURI: "https://failed.com"
        });

        managerEOA = address(0x5);
    }

    function testFuzz_DepositFromNonRouter(
        address randomCaller,
        uint256 serviceId
    ) public {
        vm.assume(randomCaller != router);

        vm.prank(randomCaller);

        vm.expectRevert("Caller is not the router");

        escrow.deposit(serviceId, DUMMY_FULFILLMENTREQUEST);
    }

    function testFuzz_DepositFromRouter(
        uint256 depositAmount,
        uint256 serviceId
    ) public {
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);

        vm.assume(serviceId > 0);

        FulFillmentRequest memory fuzzedRequest = FulFillmentRequest({
            payer: DUMMY_ADDRESS,
            weiAmount: depositAmount,
            fiatAmount: 10, // Keeping this constant for simplicity
            serviceRef: "01234XYZ" // Keeping this constant for simplicity
        });

        try registry.getService(serviceId) returns (Service memory) {} catch {
            Service memory newService = Service({
                serviceId: serviceId,
                beneficiary: payable(beneficiary),
                feeAmount: 0,
                fulfiller: fulfiller
            });
            registry.addService(serviceId, newService);
        }

        vm.prank(router);
        vm.deal(router, depositAmount);

        escrow.deposit{value: depositAmount}(serviceId, fuzzedRequest);

        assertEq(
            address(escrow).balance,
            depositAmount,
            "Escrow balance should match deposit amount"
        );
        assertEq(
            escrow.getDepositsFor(DUMMY_ADDRESS, serviceId),
            depositAmount,
            "Deposit amount should match"
        );
    }

    function testFuzz_PersistFulfillmentRecords(
        uint256 depositAmount,
        uint256 serviceId,
        address payer,
        uint256 fiatAmount,
        string memory serviceRef
    ) public {
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);

        vm.assume(serviceId > 0);

        vm.assume(payer != address(0) && payer != router);

        vm.assume(fiatAmount > 0 && fiatAmount <= 1000000);

        vm.assume(
            bytes(serviceRef).length > 0 && bytes(serviceRef).length <= 32
        );

        FulFillmentRequest memory fuzzedRequest = FulFillmentRequest({
            payer: payer,
            weiAmount: depositAmount,
            fiatAmount: fiatAmount,
            serviceRef: serviceRef
        });

        try registry.getService(serviceId) returns (Service memory) {
            // Service exists, do nothing
        } catch {
            // Service doesn't exist, add it
            Service memory newService = Service({
                serviceId: serviceId,
                beneficiary: payable(beneficiary),
                feeAmount: 0,
                fulfiller: fulfiller
            });
            registry.addService(serviceId, newService);
        }

        vm.prank(router);
        vm.deal(router, depositAmount);

        escrow.deposit{value: depositAmount}(serviceId, fuzzedRequest);

        uint256[] memory recordIds = escrow.recordsOf(payer);
        assertEq(recordIds.length, 1, "Should have one record");

        FulFillmentRecord memory record = escrow.record(recordIds[0]);
        assertEq(record.id, 1, "Record ID should be 1");
        assertEq(record.fulfiller, fulfiller, "Fulfiller should match");
        assertEq(record.payer, payer, "Payer should match");
        assertEq(record.weiAmount, depositAmount, "Wei amount should match");
        assertEq(record.fiatAmount, fiatAmount, "Fiat amount should match");
        assertEq(
            record.serviceRef,
            serviceRef,
            "Service reference should match"
        );
        assertEq(
            uint(record.status),
            uint(FulFillmentResultState.PENDING),
            "Status should be PENDING"
        );
    }

    function testFuzz_ServiceRegistrySet(address newRegistryAddress) public {
        vm.assume(
            newRegistryAddress > address(0x10) &&
                newRegistryAddress != address(registry)
        );

        vm.etch(newRegistryAddress, address(registry).code);

        vm.prank(owner);
        escrow.setFulfillableRegistry(newRegistryAddress);

        address setRegistryAddress = address(escrow._fulfillableRegistry());
        assertEq(
            setRegistryAddress,
            newRegistryAddress,
            "Service registry not set correctly"
        );

        assertTrue(
            setRegistryAddress != address(registry),
            "Old registry address should not be set"
        );
    }

    function testBeneficiaryWithdraw() public {
        vm.prank(router);
        vm.deal(router, 101);
        escrow.deposit{value: 101}(1, DUMMY_FULFILLMENTREQUEST);

        uint256[] memory records = escrow.recordsOf(DUMMY_ADDRESS);
        SUCCESS_FULFILLMENT_RESULT.id = records[0];

        vm.prank(manager);
        escrow.registerFulfillment(1, SUCCESS_FULFILLMENT_RESULT);

        uint256 preBalance = beneficiary.balance;

        vm.prank(owner);
        escrow.setManager(managerEOA);

        vm.prank(managerEOA);
        escrow.beneficiaryWithdraw(1);

        uint256 postBalance = beneficiary.balance;
        assertEq(
            postBalance,
            preBalance + 101,
            "Beneficiary balance should increase by 101"
        );

        vm.prank(owner);
        escrow.setManager(manager);
    }

    function testFuzz_ManagerAndRouterSet(
        address fuzzedManager,
        address fuzzedRouter
    ) public {
        address originalManager = escrow._manager();
        address originalRouter = escrow._router();

        vm.assume(
            fuzzedManager != address(0) &&
                fuzzedRouter != address(0) &&
                fuzzedManager != fuzzedRouter &&
                fuzzedManager != originalManager &&
                fuzzedRouter != originalRouter
        );

        vm.prank(owner);
        escrow.setManager(fuzzedManager);

        vm.prank(owner);
        escrow.setRouter(fuzzedRouter);

        address setManager = escrow._manager();
        address setRouter = escrow._router();

        assertEq(setManager, fuzzedManager, "Manager not set correctly");
        assertEq(setRouter, fuzzedRouter, "Router not set correctly");

        assertNotEq(
            setManager,
            originalManager,
            "New manager should be different from original"
        );
        assertNotEq(
            setRouter,
            originalRouter,
            "New router should be different from original"
        );

        assertNotEq(
            setManager,
            setRouter,
            "Manager and router should be different addresses"
        );
    }

    function testFuzz_RegisterFulfillmentOnlyByManager(
        uint256 depositAmount,
        uint256 serviceId,
        address payerAddress,
        address nonManagerAddress,
        address newManagerAddress
    ) public {
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);
        vm.assume(serviceId > 0);
        vm.assume(
            payerAddress != address(0) &&
                payerAddress != router &&
                payerAddress != owner
        );
        vm.assume(
            nonManagerAddress != address(0) &&
                nonManagerAddress != manager &&
                nonManagerAddress != owner
        );
        vm.assume(
            newManagerAddress != address(0) &&
                newManagerAddress != manager &&
                newManagerAddress != owner
        );

        FulFillmentRequest memory fuzzedRequest = FulFillmentRequest({
            payer: payerAddress,
            weiAmount: depositAmount,
            fiatAmount: 10, // Keeping this constant for simplicity
            serviceRef: "fuzzedRef"
        });

        try registry.getService(serviceId) returns (Service memory) {} catch {
            Service memory newService = Service({
                serviceId: serviceId,
                beneficiary: payable(beneficiary),
                feeAmount: 0,
                fulfiller: fulfiller
            });
            registry.addService(serviceId, newService);
        }

        vm.prank(router);
        vm.deal(router, depositAmount);
        escrow.deposit{value: depositAmount}(serviceId, fuzzedRequest);

        uint256[] memory payerRecordIds = escrow.recordsOf(payerAddress);
        require(payerRecordIds.length > 0, "No records found for payer");

        FulFillmentResult memory fuzzedResult = FulFillmentResult({
            status: FulFillmentResultState.SUCCESS,
            id: payerRecordIds[0],
            externalID: "fuzzedExternalId",
            receiptURI: "fuzzedReceiptUri"
        });

        vm.prank(nonManagerAddress);
        vm.expectRevert("Caller is not the manager");
        escrow.registerFulfillment(serviceId, fuzzedResult);

        vm.prank(owner);
        escrow.setManager(newManagerAddress);

        vm.prank(newManagerAddress);
        escrow.registerFulfillment(serviceId, fuzzedResult);

        FulFillmentRecord memory record = escrow.record(payerRecordIds[0]);
        assertEq(
            uint(record.status),
            uint(FulFillmentResultState.SUCCESS),
            "Fulfillment status should be SUCCESS"
        );
    }

    function testRegisterFulfillmentWithInvalidStatus() public {
        vm.prank(router);
        vm.deal(router, 101);
        escrow.deposit{value: 101}(1, DUMMY_FULFILLMENTREQUEST);

        uint256[] memory payerRecordIds = escrow.recordsOf(DUMMY_ADDRESS);
        INVALID_FULFILLMENT_RESULT.id = payerRecordIds[0];

        vm.prank(manager);
        vm.expectRevert("Unexpected status");
        escrow.registerFulfillment(1, INVALID_FULFILLMENT_RESULT);

        FulFillmentRecord memory record = escrow.record(payerRecordIds[0]);
        assertEq(uint(record.status), uint(FulFillmentResultState.PENDING));
    }

    function testFuzz_RegisterFailedFulfillment(
        uint256 depositAmount,
        uint256 serviceId,
        address payerAddress,
        address newManagerAddress,
        string memory serviceRef
    ) public {
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);
        vm.assume(serviceId > 0);
        vm.assume(
            payerAddress != address(0) &&
                payerAddress != router &&
                payerAddress != owner
        );
        vm.assume(
            newManagerAddress != address(0) &&
                newManagerAddress != manager &&
                newManagerAddress != owner
        );
        vm.assume(
            bytes(serviceRef).length > 0 && bytes(serviceRef).length <= 32
        );

        FulFillmentRequest memory fuzzedRequest = FulFillmentRequest({
            payer: payerAddress,
            weiAmount: depositAmount,
            fiatAmount: 10, // Keeping this constant for simplicity
            serviceRef: serviceRef
        });

        try registry.getService(serviceId) returns (Service memory) {
            // Service exists, do nothing
        } catch {
            // Service doesn't exist, add it
            Service memory newService = Service({
                serviceId: serviceId,
                beneficiary: payable(beneficiary),
                feeAmount: 0,
                fulfiller: fulfiller
            });
            registry.addService(serviceId, newService);
        }

        vm.prank(router);
        vm.deal(router, depositAmount);
        escrow.deposit{value: depositAmount}(serviceId, fuzzedRequest);

        uint256[] memory payerRecordIds = escrow.recordsOf(payerAddress);
        require(payerRecordIds.length > 0, "No records found for payer");

        FulFillmentResult memory failedResult = FulFillmentResult({
            status: FulFillmentResultState.FAILED,
            id: payerRecordIds[0],
            externalID: "fuzzed-failed-external-id",
            receiptURI: "https://fuzzed-failed.com"
        });

        vm.prank(owner);
        escrow.setManager(newManagerAddress);

        vm.prank(newManagerAddress);
        vm.expectEmit(true, true, false, true);
        emit RefundAuthorized(payerAddress, depositAmount);
        escrow.registerFulfillment(serviceId, failedResult);

        FulFillmentRecord memory record = escrow.record(payerRecordIds[0]);
        assertEq(
            uint(record.status),
            uint(FulFillmentResultState.FAILED),
            "Fulfillment status should be FAILED"
        );

        uint256 authorizedRefund = escrow.getRefundsFor(
            payerAddress,
            serviceId
        );
        assertEq(
            authorizedRefund,
            depositAmount,
            "Refund amount should match deposit amount"
        );
    }

    function testWithdrawRefund() public {
        vm.prank(router);
        vm.deal(router, 101);
        escrow.deposit{value: 101}(1, DUMMY_FULFILLMENTREQUEST);

        uint256[] memory payerRecordIds = escrow.recordsOf(DUMMY_ADDRESS);
        FAILED_FULFILLMENT_RESULT.id = payerRecordIds[0];

        vm.prank(owner);
        escrow.setManager(managerEOA);

        vm.prank(managerEOA);
        escrow.registerFulfillment(1, FAILED_FULFILLMENT_RESULT);

        assertEq(escrow.getRefundsFor(DUMMY_ADDRESS, 1), 101);

        vm.prank(managerEOA);
        vm.expectEmit(true, true, false, true);
        emit RefundWithdrawn(DUMMY_ADDRESS, 101);
        escrow.withdrawRefund(1, payable(DUMMY_ADDRESS));

        assertEq(escrow.getRefundsFor(DUMMY_ADDRESS, 1), 0);
    }

    function testFuzz_WithdrawRefundWithNoBalance(
        uint256 serviceId,
        address payerAddress,
        address newManagerAddress
    ) public {
        vm.assume(serviceId > 0);
        vm.assume(
            payerAddress != address(0) &&
                payerAddress != router &&
                payerAddress != owner
        );
        vm.assume(
            newManagerAddress != address(0) &&
                newManagerAddress != manager &&
                newManagerAddress != owner
        );

        try registry.getService(serviceId) returns (Service memory) {
            // Service exists, do nothing
        } catch {
            // Service doesn't exist, add it
            Service memory newService = Service({
                serviceId: serviceId,
                beneficiary: payable(beneficiary),
                feeAmount: 0,
                fulfiller: fulfiller
            });
            registry.addService(serviceId, newService);
        }

        vm.prank(owner);
        escrow.setManager(newManagerAddress);

        uint256 refundBalance = escrow.getRefundsFor(payerAddress, serviceId);
        assertEq(refundBalance, 0, "Refund balance should be 0");

        vm.prank(newManagerAddress);
        vm.expectRevert("Address is not allowed any refunds");
        escrow.withdrawRefund(serviceId, payable(payerAddress));

        refundBalance = escrow.getRefundsFor(payerAddress, serviceId);
        assertEq(refundBalance, 0, "Refund balance should still be 0");

        uint256 payerBalance = payerAddress.balance;
        vm.prank(newManagerAddress);
        vm.expectRevert("Address is not allowed any refunds");
        escrow.withdrawRefund(serviceId, payable(payerAddress));
        assertEq(
            payerAddress.balance,
            payerBalance,
            "Payer balance should not have changed"
        );
    }

    function testFuzz_RegisterAlreadyRegisteredFulfillment(
        uint256 depositAmount,
        uint256 serviceId,
        address payerAddress,
        address newManagerAddress,
        string memory serviceRef,
        string memory externalId,
        string memory receiptUri
    ) public {
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);
        vm.assume(serviceId > 0);
        vm.assume(
            payerAddress != address(0) &&
                payerAddress != router &&
                payerAddress != owner
        );
        vm.assume(
            newManagerAddress != address(0) &&
                newManagerAddress != manager &&
                newManagerAddress != owner
        );
        vm.assume(
            bytes(serviceRef).length > 0 && bytes(serviceRef).length <= 32
        );
        vm.assume(
            bytes(externalId).length > 0 && bytes(externalId).length <= 32
        );
        vm.assume(
            bytes(receiptUri).length > 0 && bytes(receiptUri).length <= 64
        );

        FulFillmentRequest memory fuzzedRequest = FulFillmentRequest({
            payer: payerAddress,
            weiAmount: depositAmount,
            fiatAmount: 10, // Keeping this constant for simplicity
            serviceRef: serviceRef
        });

        try registry.getService(serviceId) returns (Service memory) {
            // Service exists, do nothing
        } catch {
            // Service doesn't exist, add it
            Service memory newService = Service({
                serviceId: serviceId,
                beneficiary: payable(beneficiary),
                feeAmount: 0,
                fulfiller: fulfiller
            });
            registry.addService(serviceId, newService);
        }

        vm.prank(router);
        vm.deal(router, depositAmount);
        escrow.deposit{value: depositAmount}(serviceId, fuzzedRequest);

        uint256[] memory payerRecordIds = escrow.recordsOf(payerAddress);
        require(payerRecordIds.length > 0, "No records found for payer");

        FulFillmentResult memory successResult = FulFillmentResult({
            status: FulFillmentResultState.SUCCESS,
            id: payerRecordIds[0],
            externalID: externalId,
            receiptURI: receiptUri
        });

        vm.prank(owner);
        escrow.setManager(newManagerAddress);

        vm.prank(newManagerAddress);
        escrow.registerFulfillment(serviceId, successResult);

        FulFillmentRecord memory record = escrow.record(payerRecordIds[0]);
        assertEq(
            uint(record.status),
            uint(FulFillmentResultState.SUCCESS),
            "Fulfillment status should be SUCCESS"
        );

        vm.prank(newManagerAddress);
        vm.expectRevert("Fulfillment already registered");
        escrow.registerFulfillment(serviceId, successResult);

        record = escrow.record(payerRecordIds[0]);
        assertEq(
            uint(record.status),
            uint(FulFillmentResultState.SUCCESS),
            "Fulfillment status should still be SUCCESS"
        );
    }

    function testFuzz_BeneficiaryWithdrawNoBalance(
        address newManager,
        uint256 serviceId
    ) public {
        vm.assume(newManager != address(0) && newManager != escrow._manager());

        serviceId = bound(serviceId, 1, 1000);

        if (!serviceExists(serviceId)) {
            Service memory newService = Service({
                serviceId: serviceId,
                beneficiary: payable(address(0x1234)), // Use a dummy address
                feeAmount: 0,
                fulfiller: address(0x5678) // Use a dummy address
            });
            vm.prank(owner);
            registry.addService(serviceId, newService);
        }

        vm.prank(owner);
        escrow.setManager(newManager);

        vm.prank(newManager);
        vm.expectRevert("There is no balance to release.");
        escrow.beneficiaryWithdraw(serviceId);

        assertEq(
            escrow._manager(),
            newManager,
            "Manager should be set to the new address"
        );

        vm.prank(owner);
        escrow.setManager(manager);

        assertEq(
            escrow._manager(),
            manager,
            "Manager should be reset to the original address"
        );
    }

    function serviceExists(uint256 serviceId) internal view returns (bool) {
        try registry.getService(serviceId) returns (Service memory) {
            return true;
        } catch {
            return false;
        }
    }

    function testFuzz_SetManagerZeroAddress(address currentManager) public {
        vm.assume(currentManager != address(0));

        vm.prank(owner);
        escrow.setManager(currentManager);

        assertEq(
            escrow._manager(),
            currentManager,
            "Initial manager should be set correctly"
        );

        vm.prank(owner);
        vm.expectRevert("Manager cannot be the zero address");
        escrow.setManager(address(0));

        assertEq(
            escrow._manager(),
            currentManager,
            "Manager should not have changed"
        );

        address newManager = address(
            uint160(uint256(keccak256(abi.encodePacked(block.timestamp))))
        );
        vm.assume(newManager != address(0) && newManager != currentManager);

        vm.prank(owner);
        escrow.setManager(newManager);

        assertEq(
            escrow._manager(),
            newManager,
            "Manager should have changed to the new address"
        );
    }

    function testFuzz_SetRouterZeroAddress(address currentRouter) public {
        vm.assume(currentRouter != address(0));

        vm.prank(owner);
        escrow.setRouter(currentRouter);

        assertEq(
            escrow._router(),
            currentRouter,
            "Initial router should be set correctly"
        );

        vm.prank(owner);
        vm.expectRevert("Router cannot be the zero address");
        escrow.setRouter(address(0));

        assertEq(
            escrow._router(),
            currentRouter,
            "Router should not have changed"
        );

        address newRouter = address(
            uint160(uint256(keccak256(abi.encodePacked(block.timestamp))))
        );
        vm.assume(newRouter != address(0) && newRouter != currentRouter);

        vm.prank(owner);
        escrow.setRouter(newRouter);

        assertEq(
            escrow._router(),
            newRouter,
            "Router should have changed to the new address"
        );
    }

    function testFuzz_SetRouterValidAddress(address newRouter) public {
        address currentRouter = escrow._router();
        vm.assume(newRouter != address(0) && newRouter != currentRouter);

        address originalRouter = escrow._router();

        vm.prank(owner);
        escrow.setRouter(newRouter);
        assertEq(
            escrow._router(),
            newRouter,
            "Router address should be updated to the new address"
        );
        assertNotEq(
            escrow._router(),
            originalRouter,
            "Router address should be different from the original"
        );

        vm.prank(owner);
        escrow.setRouter(newRouter);

        assertEq(
            escrow._router(),
            newRouter,
            "Router address should still be set to the new address"
        );

        address anotherRouter = address(
            uint160(uint256(keccak256(abi.encodePacked(block.timestamp))))
        );
        vm.assume(
            anotherRouter != address(0) &&
                anotherRouter != newRouter &&
                anotherRouter != originalRouter
        );

        vm.prank(owner);
        escrow.setRouter(anotherRouter);

        assertEq(
            escrow._router(),
            anotherRouter,
            "Router address should be updated to another new address"
        );
        assertNotEq(
            escrow._router(),
            newRouter,
            "Router address should be different from the previous new address"
        );
        assertNotEq(
            escrow._router(),
            originalRouter,
            "Router address should be different from the original address"
        );
    }

    function testFuzz_SetFulfillableRegistryZeroAddress(
        address currentRegistry
    ) public {
        vm.assume(currentRegistry != address(0));

        vm.prank(owner);
        escrow.setFulfillableRegistry(currentRegistry);

        assertEq(
            escrow._fulfillableRegistry(),
            currentRegistry,
            "Initial fulfillable registry should be set correctly"
        );

        vm.prank(owner);
        vm.expectRevert("Fulfillable registry cannot be the zero address");
        escrow.setFulfillableRegistry(address(0));

        assertEq(
            escrow._fulfillableRegistry(),
            currentRegistry,
            "Fulfillable registry should not have changed"
        );

        address newRegistry = address(
            uint160(uint256(keccak256(abi.encodePacked(block.timestamp))))
        );
        vm.assume(newRegistry != address(0) && newRegistry != currentRegistry);

        vm.prank(owner);
        escrow.setFulfillableRegistry(newRegistry);

        assertEq(
            escrow._fulfillableRegistry(),
            newRegistry,
            "Fulfillable registry should have changed to the new address"
        );
    }

    function testWithdrawRefundNonManager() public {
        vm.prank(router);
        vm.deal(router, 101);
        escrow.deposit{value: 101}(1, DUMMY_FULFILLMENTREQUEST);

        uint256[] memory payerRecordIds = escrow.recordsOf(DUMMY_ADDRESS);
        FAILED_FULFILLMENT_RESULT.id = payerRecordIds[0];

        vm.prank(manager);
        escrow.registerFulfillment(1, FAILED_FULFILLMENT_RESULT);

        assertEq(escrow.getRefundsFor(DUMMY_ADDRESS, 1), 101);

        address nonManager = address(0x1234);
        vm.prank(nonManager);
        vm.expectRevert("Caller is not the manager");
        escrow.withdrawRefund(1, payable(DUMMY_ADDRESS));

        assertEq(escrow.getRefundsFor(DUMMY_ADDRESS, 1), 101);
    }

    function testAuthorizeRefundAmountExceedsDeport() public {
        uint256 serviceID = 1;
        address refundee = DUMMY_ADDRESS;
        uint256 depositAmount = 100;
        uint256 refundAmount = 101; // Greater than deposit

        vm.prank(router);
        vm.deal(router, depositAmount);
        escrow.deposit{value: depositAmount}(
            serviceID,
            FulFillmentRequest({
                payer: refundee,
                weiAmount: depositAmount,
                fiatAmount: 0,
                serviceRef: "test"
            })
        );
        assertEq(escrow.getDepositsFor(refundee, serviceID), depositAmount);

        vm.prank(owner);
        registry.updateServiceFeeAmount(serviceID, 1); // Set fee to 1 wei

        vm.prank(manager);
        vm.expectRevert("There is not enough balance to be released");

        escrow.registerFulfillment(
            serviceID,
            FulFillmentResult({
                status: FulFillmentResultState.FAILED,
                id: 1,
                externalID: "test",
                receiptURI: "test"
            })
        );

        assertEq(escrow.getRefundsFor(refundee, serviceID), 0);
    }

    function testAuthorizeRefundExceedsTotalDeposit() public {
        uint256 serviceID = 1;
        address refundee = DUMMY_ADDRESS;
        uint256 initialDeposit = 100;
        uint256 additionalDeposit = 1;

        vm.prank(router);
        vm.deal(router, initialDeposit);
        escrow.deposit{value: initialDeposit}(
            serviceID,
            FulFillmentRequest({
                payer: refundee,
                weiAmount: initialDeposit,
                fiatAmount: 0,
                serviceRef: "test"
            })
        );

        vm.prank(manager);
        escrow.registerFulfillment(
            serviceID,
            FulFillmentResult({
                status: FulFillmentResultState.FAILED,
                id: 1,
                externalID: "test",
                receiptURI: "test"
            })
        );

        assertEq(escrow.getRefundsFor(refundee, serviceID), initialDeposit);

        vm.prank(router);
        vm.deal(router, additionalDeposit);
        escrow.deposit{value: additionalDeposit}(
            serviceID,
            FulFillmentRequest({
                payer: refundee,
                weiAmount: additionalDeposit,
                fiatAmount: 0,
                serviceRef: "test2"
            })
        );

        vm.prank(manager);
        vm.expectRevert(
            "Total refunds would be bigger than the total in escrow"
        );
        escrow.registerFulfillment(
            serviceID,
            FulFillmentResult({
                status: FulFillmentResultState.FAILED,
                id: 2,
                externalID: "test2",
                receiptURI: "test2"
            })
        );

        assertEq(escrow.getRefundsFor(refundee, serviceID), initialDeposit);
    }

    function testRegisterNonExistentFulfillment() public {
        uint256 serviceID = 1;
        uint256 nonExistentFulfillmentId = 999; // An ID that doesn't exist

        vm.prank(owner);
        escrow.setManager(address(this));

        vm.expectRevert("Fulfillment record does not exist");
        escrow.registerFulfillment(
            serviceID,
            FulFillmentResult({
                status: FulFillmentResultState.SUCCESS,
                id: nonExistentFulfillmentId,
                externalID: "test",
                receiptURI: "test"
            })
        );
    }

    function testRegisterFulfillmentInsufficientBalance() public {
        uint256 serviceID = 1;
        uint256 depositAmount = 100;
        uint256 fulfillmentAmount = 90;
        uint256 feeAmount = 20; // This makes total_amount (90 + 20 = 110) greater than depositAmount (100)

        vm.prank(owner);
        try registry.getService(serviceID) returns (
            Service memory existingService
        ) {
            registry.updateServiceFeeAmount(serviceID, feeAmount);
            registry.updateServiceBeneficiary(serviceID, payable(beneficiary));
            registry.updateServiceFulfiller(serviceID, fulfiller);
        } catch {
            registry.addService(
                serviceID,
                Service({
                    serviceId: serviceID,
                    beneficiary: payable(beneficiary),
                    feeAmount: feeAmount,
                    fulfiller: fulfiller
                })
            );
        }

        vm.prank(router);
        vm.deal(router, depositAmount);
        escrow.deposit{value: depositAmount}(
            serviceID,
            FulFillmentRequest({
                payer: DUMMY_ADDRESS,
                weiAmount: fulfillmentAmount,
                fiatAmount: 0,
                serviceRef: "test"
            })
        );

        uint256[] memory recordIds = escrow.recordsOf(DUMMY_ADDRESS);
        require(recordIds.length > 0, "No fulfillment record created");
        uint256 fulfillmentId = recordIds[0];

        vm.prank(manager);
        vm.expectRevert("There is not enough balance to be released");
        escrow.registerFulfillment(
            serviceID,
            FulFillmentResult({
                status: FulFillmentResultState.SUCCESS,
                id: fulfillmentId,
                externalID: "test",
                receiptURI: "test"
            })
        );

        FulFillmentRecord memory record = escrow.record(fulfillmentId);
        assertEq(uint(record.status), uint(FulFillmentResultState.PENDING));

        assertEq(
            escrow.getDepositsFor(DUMMY_ADDRESS, serviceID),
            depositAmount
        );
    }

    function testFuzz_BeneficiaryWithdrawNotManager(
        uint256 serviceId,
        uint256 depositAmount,
        address nonManager
    ) public {
        vm.assume(serviceId > 0);
        vm.assume(depositAmount > 0 && depositAmount <= 1000 ether);
        vm.assume(
            nonManager != address(0) &&
                nonManager != manager &&
                nonManager != owner
        );

        try registry.getService(serviceId) returns (Service memory) {} catch {
            // Service doesn't exist, add it
            Service memory newService = Service({
                serviceId: serviceId,
                beneficiary: payable(beneficiary),
                feeAmount: 0,
                fulfiller: fulfiller
            });
            vm.prank(owner);
            registry.addService(serviceId, newService);
        }

        vm.prank(router);
        vm.deal(router, depositAmount);
        FulFillmentRequest memory request = FulFillmentRequest({
            payer: DUMMY_ADDRESS,
            weiAmount: depositAmount,
            fiatAmount: 10,
            serviceRef: "fuzzedRef"
        });
        escrow.deposit{value: depositAmount}(serviceId, request);

        uint256[] memory records = escrow.recordsOf(DUMMY_ADDRESS);
        require(records.length > 0, "No records found");

        FulFillmentResult memory successResult = FulFillmentResult({
            status: FulFillmentResultState.SUCCESS,
            id: records[0],
            externalID: "fuzzed-success-external-id",
            receiptURI: "https://fuzzed-success.com"
        });
        vm.prank(manager);
        escrow.registerFulfillment(serviceId, successResult);

        uint256 releaseableBalance = escrow._releaseablePool(serviceId);
        assertGt(
            releaseableBalance,
            0,
            "Releasable pool should have a balance"
        );

        uint256 initialBeneficiaryBalance = beneficiary.balance;
        uint256 initialReleaseableBalance = escrow._releaseablePool(serviceId);

        vm.prank(nonManager);
        vm.expectRevert("Caller is not the manager");
        escrow.beneficiaryWithdraw(serviceId);

        assertEq(
            beneficiary.balance,
            initialBeneficiaryBalance,
            "Beneficiary balance should not change"
        );

        assertEq(
            escrow._releaseablePool(serviceId),
            initialReleaseableBalance,
            "Releasable pool should not change"
        );

        vm.prank(manager);
        escrow.beneficiaryWithdraw(serviceId);

        assertEq(
            beneficiary.balance,
            initialBeneficiaryBalance + initialReleaseableBalance,
            "Beneficiary should receive the funds when withdrawn by the manager"
        );

        assertEq(
            escrow._releaseablePool(serviceId),
            0,
            "Releasable pool should be empty after withdrawal"
        );
    }

    function testAuthorizeRefundAmountExceedsDeposit() public {
        uint256 serviceID = 1;
        address refundee = DUMMY_ADDRESS;
        uint256 depositAmount = 100;
        uint256 feeAmount = 1; // This will make total_amount (100 + 1 = 101) greater than depositAmount (100)

        vm.prank(owner);
        try registry.getService(serviceID) returns (
            Service memory existingService
        ) {
            registry.updateServiceBeneficiary(serviceID, payable(beneficiary));
            registry.updateServiceFeeAmount(serviceID, feeAmount);
            registry.updateServiceFulfiller(serviceID, fulfiller);
        } catch {
            registry.addService(
                serviceID,
                Service({
                    serviceId: serviceID,
                    beneficiary: payable(beneficiary),
                    feeAmount: feeAmount,
                    fulfiller: fulfiller
                })
            );
        }

        vm.prank(router);
        vm.deal(router, depositAmount);
        escrow.deposit{value: depositAmount}(
            serviceID,
            FulFillmentRequest({
                payer: refundee,
                weiAmount: depositAmount,
                fiatAmount: 0,
                serviceRef: "test"
            })
        );

        assertEq(escrow.getDepositsFor(refundee, serviceID), depositAmount);

        uint256[] memory recordIds = escrow.recordsOf(refundee);
        require(recordIds.length > 0, "No fulfillment record created");
        uint256 fulfillmentId = recordIds[0];

        vm.prank(manager);
        vm.expectRevert("There is not enough balance to be released");
        escrow.registerFulfillment(
            serviceID,
            FulFillmentResult({
                status: FulFillmentResultState.FAILED,
                id: fulfillmentId,
                externalID: "test",
                receiptURI: "test"
            })
        );

        assertEq(escrow.getRefundsFor(refundee, serviceID), 0);
    }
}
