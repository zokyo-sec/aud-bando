// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/BandoRouterV1.sol";
import "../contracts/BandoFulfillableV1.sol";
import "../contracts/BandoERC20FulfillableV1.sol";
import "../contracts/periphery/registry/FulfillableRegistry.sol";
import "../contracts/periphery/registry/ERC20TokenRegistry.sol";
import "../contracts/BandoFulfillmentManagerV1.sol";
import "../contracts/test/TestERC20.sol";
import "../contracts/test/RouterUpgradeTester.sol";
import "../contracts/libraries/FulfillmentRequestLib.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../contracts/IBandoFulfillable.sol";
import "../contracts/periphery/registry/IFulfillableRegistry.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract BandoRouterV1Test is Test {
    BandoRouterV1 public router;
    BandoFulfillableV1 public escrow;
    BandoERC20FulfillableV1 public erc20Escrow;
    FulfillableRegistry public registry;
    ERC20TokenRegistry public tokenRegistry;
    BandoFulfillmentManagerV1 public manager;
    DemoToken public erc20Test;
    RouterUpgradeTester public v2;

    address public owner;
    address public beneficiary;
    address public fulfiller;
    string public validRef;

    event ServiceRequested(uint256 serviceID, FulFillmentRequest request);
    event ERC20ServiceRequested(
        uint256 serviceID,
        ERC20FulFillmentRequest request
    );
    error OwnableUnauthorizedAccount(address account);
    error OwnableInvalidOwner(address owner);

    FulFillmentRequest public DUMMY_FULFILLMENTREQUEST;
    FulFillmentRequest public DUMMY_VALID_FULFILLMENTREQUEST;
    ERC20FulFillmentRequest public DUMMY_ERC20_FULFILLMENTREQUEST;
    ERC20FulFillmentRequest public DUMMY_VALID_ERC20_FULFILLMENTREQUEST;

    function setUp() public {
        owner = address(this);
        beneficiary = payable(makeAddr("beneficiary"));
        fulfiller = payable(makeAddr("fulfiller"));
        validRef = "validRef123";

        router = new BandoRouterV1();
        escrow = new BandoFulfillableV1();
        erc20Escrow = new BandoERC20FulfillableV1();
        registry = new FulfillableRegistry();
        tokenRegistry = new ERC20TokenRegistry();
        manager = new BandoFulfillmentManagerV1();
        erc20Test = new DemoToken();

        v2 = new RouterUpgradeTester();

        router.initialize();
        escrow.initialize();
        erc20Escrow.initialize();
        registry.initialize();
        tokenRegistry.initialize();
        manager.initialize();
        v2.initialize();

        uint256 feeAmount = 0.1 ether;
        escrow.setManager(address(manager));
        escrow.setFulfillableRegistry(address(registry));
        escrow.setRouter(address(router));
        erc20Escrow.setManager(address(manager));
        erc20Escrow.setFulfillableRegistry(address(registry));
        erc20Escrow.setRouter(address(router));
        registry.setManager(address(manager));
        manager.setServiceRegistry(address(registry));
        manager.setEscrow(payable(address(escrow)));
        manager.setERC20Escrow(payable(address(erc20Escrow)));
        router.setFulfillableRegistry(address(registry));
        router.setTokenRegistry(address(tokenRegistry));
        router.setEscrow(payable(address(escrow)));
        router.setERC20Escrow(payable(address(erc20Escrow)));

        manager.setService(1, feeAmount, fulfiller, payable(beneficiary));
        manager.setServiceRef(1, validRef);

        tokenRegistry.addToken(address(erc20Test));

        DUMMY_FULFILLMENTREQUEST = FulFillmentRequest({
            payer: address(0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A),
            weiAmount: 999,
            fiatAmount: 10,
            serviceRef: "01234XYZ"
        });

        DUMMY_VALID_FULFILLMENTREQUEST = FulFillmentRequest({
            payer: address(0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A),
            weiAmount: 11000 ether,
            fiatAmount: 101,
            serviceRef: "012345678912"
        });

        DUMMY_ERC20_FULFILLMENTREQUEST = ERC20FulFillmentRequest({
            payer: address(0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A),
            tokenAmount: 100,
            fiatAmount: 10,
            serviceRef: "01234XYZ",
            token: address(erc20Test)
        });

        DUMMY_VALID_ERC20_FULFILLMENTREQUEST = ERC20FulFillmentRequest({
            payer: address(0x5981Bfc1A21978E82E8AF7C76b770CE42C777c3A),
            tokenAmount: 100,
            fiatAmount: 10,
            serviceRef: "012345678912",
            token: address(erc20Test)
        });

        erc20Test.approve(address(router), 10000000000);
    }

    function testFuzz_ServiceRegistrySetCorrectly(address newRegistry) public {
        vm.assume(newRegistry != address(0));

        address originalRegistry = router._fulfillableRegistry();

        vm.prank(owner);
        router.setFulfillableRegistry(newRegistry);

        assertEq(
            router._fulfillableRegistry(),
            newRegistry,
            "Service registry not set correctly"
        );

        assertNotEq(
            router._fulfillableRegistry(),
            originalRegistry,
            "New registry should be different from original"
        );

        vm.expectRevert("Fulfillable registry cannot be the zero address");
        vm.prank(owner);
        router.setFulfillableRegistry(address(0));

        assertEq(
            router._fulfillableRegistry(),
            newRegistry,
            "Registry should not change after failed attempt"
        );
    }

    function testFuzz_TokenRegistrySetCorrectly(
        address newTokenRegistry
    ) public {
        vm.assume(newTokenRegistry != address(0));

        address originalTokenRegistry = router._tokenRegistry();

        vm.prank(owner);
        router.setTokenRegistry(newTokenRegistry);

        assertEq(
            router._tokenRegistry(),
            newTokenRegistry,
            "Token registry not set correctly"
        );

        assertNotEq(
            router._tokenRegistry(),
            originalTokenRegistry,
            "New token registry should be different from original"
        );

        vm.expectRevert("Token registry cannot be the zero address");
        vm.prank(owner);
        router.setTokenRegistry(address(0));

        assertEq(
            router._tokenRegistry(),
            newTokenRegistry,
            "Token registry should not change after failed attempt"
        );

        address nonOwner = address(0x1234);
        vm.prank(nonOwner);
        vm.expectRevert(); // Expect any revert
        router.setTokenRegistry(address(0x5678));

        assertEq(
            router._tokenRegistry(),
            newTokenRegistry,
            "Token registry should not change after non-owner attempt"
        );

        vm.prank(owner);
        router.setTokenRegistry(originalTokenRegistry);

        assertEq(
            router._tokenRegistry(),
            originalTokenRegistry,
            "Token registry should be set back to original address"
        );
    }

    function testFuzz_EscrowSetCorrectly(address newEscrow) public {
        address originalEscrow = router._escrow();

        vm.assume(newEscrow != address(0) && newEscrow != originalEscrow);

        vm.prank(owner);
        router.setEscrow(payable(newEscrow));

        assertEq(router._escrow(), newEscrow, "Escrow not set correctly");

        assertNotEq(
            router._escrow(),
            originalEscrow,
            "New escrow should be different from original"
        );

        vm.expectRevert("Escrow cannot be the zero address");
        vm.prank(owner);
        router.setEscrow(payable(address(0)));

        assertEq(
            router._escrow(),
            newEscrow,
            "Escrow should not change after failed attempt"
        );

        address nonOwner = address(0x1234);
        vm.prank(nonOwner);
        vm.expectRevert(); // Expect any revert
        router.setEscrow(payable(address(0x5678)));

        assertEq(
            router._escrow(),
            newEscrow,
            "Escrow should not change after non-owner attempt"
        );
    }

    function testFuzz_ERC20EscrowSetCorrectly(address newERC20Escrow) public {
        vm.assume(newERC20Escrow != address(0));

        address originalERC20Escrow = router._erc20Escrow();

        vm.prank(owner);
        router.setERC20Escrow(payable(newERC20Escrow));

        assertEq(
            router._erc20Escrow(),
            newERC20Escrow,
            "ERC20 escrow not set correctly"
        );

        assertNotEq(
            router._erc20Escrow(),
            originalERC20Escrow,
            "New ERC20 escrow should be different from original"
        );

        vm.expectRevert("ERC20 escrow cannot be the zero address");
        vm.prank(owner);
        router.setERC20Escrow(payable(address(0)));

        assertEq(
            router._erc20Escrow(),
            newERC20Escrow,
            "ERC20 escrow should not change after failed attempt"
        );

        address nonOwner = address(0x1234);
        vm.prank(nonOwner);
        vm.expectRevert(); // Expect any revert
        router.setERC20Escrow(payable(address(0x5678)));

        assertEq(
            router._erc20Escrow(),
            newERC20Escrow,
            "ERC20 escrow should not change after non-owner attempt"
        );

        address anotherERC20Escrow = address(0x9876);
        vm.prank(owner);
        router.setERC20Escrow(payable(anotherERC20Escrow));
        assertEq(
            router._erc20Escrow(),
            anotherERC20Escrow,
            "ERC20 escrow should be updatable multiple times by owner"
        );
    }

    function testFuzz_OwnershipTransferred(address newOwner) public {
        vm.assume(newOwner != address(0) && newOwner != address(this));

        address originalOwner = router.owner();

        assertEq(
            originalOwner,
            address(this),
            "Initial ownership should be the test contract"
        );

        vm.prank(address(this));
        router.transferOwnership(newOwner);

        assertEq(
            router.owner(),
            newOwner,
            "Ownership should be transferred to the new owner"
        );

        vm.expectRevert(); // Expect any revert
        vm.prank(address(this));
        router.transferOwnership(address(0xdead));

        vm.prank(newOwner);
        router.transferOwnership(address(this));

        assertEq(
            router.owner(),
            address(this),
            "Ownership should be transferred back to the test contract"
        );

        vm.expectRevert(); // Expect any revert
        vm.prank(address(this));
        router.transferOwnership(address(0));

        // Ensure ownership hasn't changed after failed attempts
        assertEq(
            router.owner(),
            address(this),
            "Ownership should not change after failed attempts"
        );
    }

    function testUpgradeSimulation() public {
        RouterUpgradeTester newImplementation = new RouterUpgradeTester();

        address currentImpl = address(router);

        RouterUpgradeTester upgradedRouter = new RouterUpgradeTester();
        upgradedRouter.initialize(); // Initialize the new instance

        upgradedRouter.setFulfillableRegistry(router._fulfillableRegistry());
        upgradedRouter.setTokenRegistry(router._tokenRegistry());
        upgradedRouter.setEscrow(router._escrow());
        upgradedRouter.setERC20Escrow(router._erc20Escrow());

        assertEq(
            upgradedRouter._fulfillableRegistry(),
            router._fulfillableRegistry(),
            "Fulfillable registry should be the same"
        );
        assertEq(
            upgradedRouter._tokenRegistry(),
            router._tokenRegistry(),
            "Token registry should be the same"
        );
        assertEq(
            upgradedRouter._escrow(),
            router._escrow(),
            "Escrow should be the same"
        );
        assertEq(
            upgradedRouter._erc20Escrow(),
            router._erc20Escrow(),
            "ERC20 escrow should be the same"
        );

        assertTrue(
            upgradedRouter.isUpgrade(),
            "New function should be accessible in upgraded router"
        );
    }

    function testFuzz_OnlyOwnerCanPause(address nonOwner) public {
        vm.assume(nonOwner != address(0) && nonOwner != owner);

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                nonOwner
            )
        );
        router.pause();

        assertFalse(router.paused(), "Contract should not be paused");

        vm.prank(owner);
        router.pause();

        assertTrue(router.paused(), "Contract should be paused");

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                nonOwner
            )
        );
        router.pause();

        assertTrue(router.paused(), "Contract should still be paused");

        vm.prank(owner);
        router.unpause();

        assertFalse(router.paused(), "Contract should be unpaused");
    }

    function testFuzz_OnlyOwnerCanUnpause(address nonOwner) public {
        vm.assume(nonOwner != address(0) && nonOwner != owner);

        vm.prank(owner);
        router.pause();

        assertTrue(router.paused(), "Contract should be paused");

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                nonOwner
            )
        );
        router.unpause();

        assertTrue(
            router.paused(),
            "Contract should still be paused after non-owner attempt"
        );

        vm.prank(owner);
        router.unpause();

        assertFalse(router.paused(), "Contract should be unpaused");

        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                nonOwner
            )
        );
        router.unpause();

        assertFalse(
            router.paused(),
            "Contract should still be unpaused after second non-owner attempt"
        );

        // Do not try to unpause again from owner account, as it's already unpaused
    }

    function testFuzz_OnlyOwnerCanCallUpgradeMethod(
        address invalidOwner
    ) public {
        vm.assume(invalidOwner != address(0) && invalidOwner != owner);

        address validOwner = owner;

        assertFalse(
            v2.owner() == invalidOwner,
            "Invalid owner should not be the current owner"
        );

        assertEq(
            v2.owner(),
            validOwner,
            "Valid owner should be the current owner"
        );

        vm.prank(invalidOwner);
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                invalidOwner
            )
        );
        v2.isUpgrade();

        vm.prank(validOwner);
        assertTrue(
            v2.isUpgrade(),
            "isUpgrade should return true when called by owner"
        );

        vm.prank(validOwner);
        v2.transferOwnership(invalidOwner);

        vm.prank(invalidOwner);
        assertTrue(
            v2.isUpgrade(),
            "isUpgrade should return true when called by new owner"
        );

        vm.prank(validOwner);
        vm.expectRevert(
            abi.encodeWithSignature(
                "OwnableUnauthorizedAccount(address)",
                validOwner
            )
        );
        v2.isUpgrade();
        vm.prank(invalidOwner);
        v2.transferOwnership(validOwner);
    }

    function testFuzz_OwnerCanTransferOwnership(address newOwner) public {
        vm.assume(newOwner != address(0) && newOwner != owner);

        address oldOwner = owner;

        assertEq(v2.owner(), oldOwner, "Initial owner should be the old owner");

        vm.prank(oldOwner);
        v2.transferOwnership(newOwner);
        assertEq(
            v2.owner(),
            newOwner,
            "Ownership should be transferred to new owner"
        );

        vm.prank(oldOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                oldOwner
            )
        );
        v2.transferOwnership(oldOwner);

        assertEq(
            v2.owner(),
            newOwner,
            "Ownership should still be with new owner after failed attempt"
        );

        vm.prank(newOwner);
        v2.transferOwnership(oldOwner);
        assertEq(
            v2.owner(),
            oldOwner,
            "Ownership should be transferred back to old owner"
        );

        vm.prank(oldOwner);
        vm.expectRevert(
            abi.encodeWithSelector(OwnableInvalidOwner.selector, address(0))
        );
        v2.transferOwnership(address(0));

        assertEq(
            v2.owner(),
            oldOwner,
            "Ownership should still be with old owner after failed attempt"
        );

        address nonOwner = address(0x1234);
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        v2.transferOwnership(nonOwner);

        assertEq(
            v2.owner(),
            oldOwner,
            "Ownership should still be with old owner after non-owner attempt"
        );
    }

    function testFailWhenServiceIdNotSetInRegistry() public {
        vm.prank(beneficiary);
        vm.expectRevert("FulfillableRegistry: Service does not exist");
        v2.requestService{value: 1000 wei}(2, DUMMY_FULFILLMENTREQUEST);
    }

    function testFailWhenAmountIsZero() public {
        vm.expectRevert("InsufficientAmount()");
        v2.requestService{value: 0}(1, DUMMY_VALID_FULFILLMENTREQUEST);
    }

    function testFailWithInsufficientFunds() public {
        Service memory service = registry.getService(1);
        uint256 total = DUMMY_VALID_FULFILLMENTREQUEST.weiAmount +
            service.feeAmount;

        vm.deal(address(this), total - 1);

        vm.expectRevert(abi.encodeWithSignature("OutOfFunds()"));

        v2.requestService{value: total}(1, DUMMY_VALID_FULFILLMENTREQUEST);
    }

    function testFailWithInvalidRef() public {
        string memory invalidRef = "1234567890";
        FulFillmentRequest
            memory invalidRequest = DUMMY_VALID_FULFILLMENTREQUEST;
        invalidRequest.serviceRef = invalidRef;

        vm.expectRevert(
            abi.encodeWithSelector(FulfillmentRequestLib.InvalidRef.selector)
        );
        v2.requestService{value: 1 ether}(1, invalidRequest);
    }

    function testFailERC20ServiceWithNonExistentService() public {
        vm.prank(beneficiary);
        vm.expectRevert("FulfillableRegistry: Service does not exist");
        v2.requestERC20Service(2, DUMMY_ERC20_FULFILLMENTREQUEST);
    }

    function testFailERC20ServiceWithZeroAmount() public {
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.tokenAmount = 0;
        vm.expectRevert("InsufficientAmount()");
        v2.requestERC20Service(1, DUMMY_VALID_ERC20_FULFILLMENTREQUEST);
    }

    function testFailERC20ServiceWithInsufficientBalance() public {
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.payer = fulfiller;
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.serviceRef = validRef;
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.tokenAmount = 100;

        vm.startPrank(fulfiller);
        erc20Test.approve(address(v2), 100);
        vm.expectRevert("BandoRouterV1: Insufficient balance");
        v2.requestERC20Service(1, DUMMY_VALID_ERC20_FULFILLMENTREQUEST);
        vm.stopPrank();
    }

    function testFailERC20ServiceWithInsufficientAllowance() public {
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.payer = fulfiller;
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.serviceRef = validRef;
        DUMMY_VALID_ERC20_FULFILLMENTREQUEST.tokenAmount = 1000;

        erc20Test.transfer(fulfiller, 1000);

        vm.startPrank(fulfiller);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientAllowance.selector,
                address(v2),
                100,
                1000
            )
        );
        v2.requestERC20Service(1, DUMMY_VALID_ERC20_FULFILLMENTREQUEST);
        vm.stopPrank();
    }

    function testFailERC20ServiceWithInvalidRef() public {
        string memory invalidRef = "1234567890";
        ERC20FulFillmentRequest
            memory invalidRequest = DUMMY_ERC20_FULFILLMENTREQUEST;
        invalidRequest.serviceRef = invalidRef;

        vm.expectRevert(
            abi.encodeWithSelector(FulfillmentRequestLib.InvalidRef.selector)
        );
        v2.requestERC20Service(1, invalidRequest);
    }

    function testFuzz_SetFulfillableRegistryZeroAddress(
        address nonZeroAddress
    ) public {
        vm.assume(nonZeroAddress != address(0));

        address originalRegistry = v2._fulfillableRegistry();

        vm.prank(owner);
        v2.setFulfillableRegistry(nonZeroAddress);

        assertEq(
            v2._fulfillableRegistry(),
            nonZeroAddress,
            "Fulfillable registry should be set to non-zero address"
        );

        vm.prank(owner);
        vm.expectRevert("Fulfillable registry cannot be the zero address");
        v2.setFulfillableRegistry(address(0));

        assertEq(
            v2._fulfillableRegistry(),
            nonZeroAddress,
            "Fulfillable registry should not have changed"
        );

        address nonOwner = address(0x1234);
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        v2.setFulfillableRegistry(address(0x5678));

        assertEq(
            v2._fulfillableRegistry(),
            nonZeroAddress,
            "Fulfillable registry should not change after non-owner attempt"
        );
    }

    function testFuzz_SetTokenRegistryZeroAddress(address validAddress) public {
        vm.assume(validAddress != address(0));

        address originalRegistry = v2._tokenRegistry();

        vm.startPrank(owner);

        v2.setTokenRegistry(validAddress);

        assertEq(
            v2._tokenRegistry(),
            validAddress,
            "Token registry should be set to the valid address"
        );

        vm.expectRevert("Token registry cannot be the zero address");
        v2.setTokenRegistry(address(0));

        assertEq(
            v2._tokenRegistry(),
            validAddress,
            "Token registry should not have changed"
        );

        vm.stopPrank();

        address nonOwner = address(0x1234);
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        v2.setTokenRegistry(address(0x5678));

        assertEq(
            v2._tokenRegistry(),
            validAddress,
            "Token registry should not change after non-owner attempt"
        );
    }

    function testFuzz_SetEscrowZeroAddress(
        address payable validAddress
    ) public {
        vm.assume(validAddress != address(0));

        address payable originalEscrow = v2._escrow();

        vm.startPrank(owner);

        v2.setEscrow(validAddress);

        assertEq(
            v2._escrow(),
            validAddress,
            "Escrow should be set to the valid address"
        );

        vm.expectRevert("Escrow cannot be the zero address");
        v2.setEscrow(payable(address(0)));

        assertEq(v2._escrow(), validAddress, "Escrow should not have changed");

        vm.stopPrank();

        address nonOwner = address(0x1234);
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        v2.setEscrow(payable(address(0x5678)));

        assertEq(
            v2._escrow(),
            validAddress,
            "Escrow should not change after non-owner attempt"
        );
    }

    function testFuzz_SetERC20EscrowZeroAddress(
        address payable validAddress
    ) public {
        vm.assume(validAddress != address(0));

        address payable originalERC20Escrow = v2._erc20Escrow();

        vm.startPrank(owner);

        v2.setERC20Escrow(validAddress);

        assertEq(
            v2._erc20Escrow(),
            validAddress,
            "ERC20 escrow should be set to the valid address"
        );

        vm.expectRevert("ERC20 escrow cannot be the zero address");
        v2.setERC20Escrow(payable(address(0)));

        assertEq(
            v2._erc20Escrow(),
            validAddress,
            "ERC20 escrow should not have changed"
        );

        vm.stopPrank();

        address nonOwner = address(0x1234);
        vm.prank(nonOwner);
        vm.expectRevert(
            abi.encodeWithSelector(
                OwnableUnauthorizedAccount.selector,
                nonOwner
            )
        );
        v2.setERC20Escrow(payable(address(0x5678)));

        assertEq(
            v2._erc20Escrow(),
            validAddress,
            "ERC20 escrow should not change after non-owner attempt"
        );
    }

    function testRequestERC20ServiceInsufficientBalance() public {
        uint256 serviceID = 1;
        uint256 tokenAmount = 100;
        address payer = address(this);

        ERC20FulFillmentRequest memory request = ERC20FulFillmentRequest({
            payer: payer,
            tokenAmount: tokenAmount,
            fiatAmount: 10,
            serviceRef: validRef,
            token: address(erc20Test)
        });

        uint256 balance = erc20Test.balanceOf(address(this));
        erc20Test.transfer(address(0x1), balance - tokenAmount + 1); // Leave 1 token less than required

        erc20Test.approve(address(v2), tokenAmount);

        v2.setFulfillableRegistry(address(registry));
        v2.setTokenRegistry(address(tokenRegistry));
        v2.setERC20Escrow(payable(address(erc20Escrow)));

        escrow.setRouter(address(v2));
        erc20Escrow.setRouter(address(v2));

        console.log("Router set in escrow:", escrow._router());
        console.log("Router set in erc20Escrow:", erc20Escrow._router());
        console.log("Test contract address:", address(this));
        console.log("v2 address:", address(v2));
        console.log(
            "Test contract balance:",
            erc20Test.balanceOf(address(this))
        );

        vm.expectRevert("BandoRouterV1: Insufficient balance");
        v2.requestERC20Service(serviceID, request);
    }

    function testRequestERC20ServiceSuccess() public {
        uint256 serviceID = 1;
        uint256 tokenAmount = 10000;
        address payer = address(this);

        ERC20FulFillmentRequest memory request = ERC20FulFillmentRequest({
            payer: payer,
            tokenAmount: tokenAmount,
            fiatAmount: 10,
            serviceRef: validRef,
            token: address(erc20Test)
        });

        erc20Test.transfer(payer, tokenAmount);

        erc20Test.approve(address(v2), tokenAmount);

        v2.setFulfillableRegistry(address(registry));
        v2.setTokenRegistry(address(tokenRegistry));
        v2.setERC20Escrow(payable(address(erc20Escrow)));

        escrow.setRouter(address(v2));
        erc20Escrow.setRouter(address(v2));

        console.log("Router set in escrow:", escrow._router());
        console.log("Router set in erc20Escrow:", erc20Escrow._router());
        console.log("Test contract address:", address(this));
        console.log("v2 address:", address(v2));

        vm.expectEmit(true, true, false, true);
        emit ERC20ServiceRequested(serviceID, request);

        vm.prank(payer);
        (bool success, bytes memory returnData) = address(v2).call(
            abi.encodeWithSelector(
                v2.requestERC20Service.selector,
                serviceID,
                request
            )
        );

        assertTrue(success, "ERC20 service request should be successful");

        assertEq(
            erc20Test.balanceOf(address(erc20Escrow)),
            tokenAmount,
            "ERC20 escrow should have received the tokens"
        );
    }

    function testRequestERC20ServiceInvalidTransferReturn() public {
        uint256 serviceID = 1;
        uint256 tokenAmount = 100;
        address payer = address(this);

        ERC20FulFillmentRequest memory request = ERC20FulFillmentRequest({
            payer: payer,
            tokenAmount: tokenAmount,
            fiatAmount: 10,
            serviceRef: validRef,
            token: address(erc20Test)
        });

        erc20Test.transfer(payer, tokenAmount * 2);

        erc20Test.approve(address(v2), tokenAmount);

        v2.setFulfillableRegistry(address(registry));
        v2.setTokenRegistry(address(tokenRegistry));
        v2.setERC20Escrow(payable(address(erc20Escrow)));

        escrow.setRouter(address(v2));
        erc20Escrow.setRouter(address(v2));

        console.log("Initial payer balance:", erc20Test.balanceOf(payer));

        vm.mockCall(
            address(erc20Test),
            abi.encodeWithSelector(
                IERC20.transferFrom.selector,
                payer,
                address(erc20Escrow),
                tokenAmount
            ),
            abi.encode(true)
        );
        vm.mockCall(
            address(erc20Test),
            abi.encodeWithSelector(IERC20.balanceOf.selector, payer),
            abi.encode(tokenAmount * 2) // Simulate balance not changing after transfer
        );

        vm.expectRevert("BandoRouterV1: ERC20 invalid transfer return");
        v2.requestERC20Service(serviceID, request);

        vm.clearMockedCalls();
    }

    function testFuzz_RequestServiceSuccess(
        uint256 serviceID,
        uint256 weiAmount,
        uint256 fiatAmount
    ) public {
        vm.assume(serviceID > 0);

        weiAmount = bound(weiAmount, 0.1 ether, 100 ether);
        fiatAmount = bound(fiatAmount, 1, 1000000); // Assuming fiat amount in cents

        string memory validServiceRef = "validRef123"; // Replace with a known valid ref

        FulFillmentRequest memory request = FulFillmentRequest({
            payer: address(this),
            weiAmount: weiAmount,
            fiatAmount: fiatAmount,
            serviceRef: validServiceRef
        });

        Service memory service;
        try registry.getService(serviceID) returns (Service memory _service) {
            service = _service;
        } catch {
            vm.assume(false);
            return;
        }

        uint256 totalAmount = weiAmount + service.feeAmount;

        v2.setEscrow(payable(address(escrow)));
        v2.setFulfillableRegistry(address(registry));
        escrow.setRouter(address(v2));

        console.log("Router address:", address(v2));
        console.log("Escrow address:", address(escrow));
        console.log("Registry address:", address(registry));
        console.log("Router's escrow address:", v2._escrow());
        console.log("Escrow's router address:", escrow._router());

        vm.expectEmit(true, true, false, true);
        emit ServiceRequested(serviceID, request);

        vm.expectCall(
            address(escrow),
            weiAmount,
            abi.encodeWithSelector(
                IBandoFulfillable.deposit.selector,
                serviceID,
                request
            )
        );

        vm.deal(address(this), totalAmount); // Ensure the contract has enough balance
        bool success = v2.requestService{value: totalAmount}(
            serviceID,
            request
        );

        assertTrue(success, "Service request should be successful");

        assertEq(
            escrow.getDepositsFor(address(this), serviceID),
            weiAmount,
            "Deposit amount should match"
        );
        assertEq(
            address(escrow).balance,
            weiAmount,
            "Escrow balance should match weiAmount"
        );
        assertEq(
            address(v2).balance,
            service.feeAmount,
            "Router balance should match feeAmount"
        );
    }
}
