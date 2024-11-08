// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/libraries/FulfillmentRequestLib.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract TestHelper {
    using FulfillmentRequestLib for *;

    function validateRequestHelper(
        uint256 serviceID,
        FulFillmentRequest memory request,
        address fulfillableRegistry
    ) external payable returns (Service memory) {
        return FulfillmentRequestLib.validateRequest(serviceID, request, fulfillableRegistry);
    }

    function validateERC20RequestHelper(
        uint256 serviceID,
        ERC20FulFillmentRequest memory request,
        address fulfillableRegistry,
        address tokenRegistry
    ) external view returns (Service memory) {
        return FulfillmentRequestLib.validateERC20Request(
            serviceID,
            request,
            fulfillableRegistry,
            tokenRegistry
        );
    }
}


contract FulfillmentRequestLibTest is Test {
    TestHelper public testHelper;
    MockFulfillableRegistry public registry;
    MockTokenRegistry public tokenRegistry;
    MockERC20 public token;

    function setUp() public {
        testHelper = new TestHelper();
        registry = new MockFulfillableRegistry();
        tokenRegistry = new MockTokenRegistry();
        token = new MockERC20("Test", "TST");
    }

    function test_validateRequest(
        uint256 serviceID,
        uint256 weiAmount,
        uint256 fiatAmount,
        string memory serviceRef,
        uint256 feeAmount
    ) public {
        // Bound values to prevent overflows
        weiAmount = bound(weiAmount, 1, 100 ether);
        fiatAmount = bound(fiatAmount, 1, 1000000);
        feeAmount = bound(feeAmount, 0.01 ether, 1 ether);
        
        FulFillmentRequest memory request = FulFillmentRequest({
            payer: msg.sender,
            weiAmount: weiAmount,
            fiatAmount: fiatAmount,
            serviceRef: serviceRef
        });

        // Setup service with payable addresses
        Service memory service = Service({
            serviceId: serviceID,
            beneficiary: payable(address(0x123)),
            feeAmount: feeAmount,
            fulfiller: payable(address(0x456))
        });

        // Mock registry responses
        registry.setService(serviceID, service);
        registry.setRefValid(serviceID, serviceRef, true);

        // Fund the helper contract
        vm.deal(address(testHelper), weiAmount + feeAmount);
        
        // Test successful validation
        Service memory returnedService = testHelper.validateRequestHelper{
            value: weiAmount + feeAmount
        }(serviceID, request, address(registry));
        
        assertEq(returnedService.serviceId, service.serviceId);
        assertEq(returnedService.feeAmount, service.feeAmount);
    }

    function test_validateRequest_Reverts(
        uint256 serviceID,
        uint256 weiAmount,
        uint256 fiatAmount,
        string memory serviceRef,
        uint256 feeAmount
    ) public {
        weiAmount = bound(weiAmount, 1, 100 ether);
        fiatAmount = bound(fiatAmount, 0, 1000000);
        feeAmount = bound(feeAmount, 0.01 ether, 1 ether);

        FulFillmentRequest memory request = FulFillmentRequest({
            payer: msg.sender,
            weiAmount: weiAmount,
            fiatAmount: fiatAmount,
            serviceRef: serviceRef
        });

        // Test zero value sent
        vm.expectRevert(FulfillmentRequestLib.InsufficientAmount.selector);
        testHelper.validateRequestHelper{value: 0}(
            serviceID,
            request,
            address(registry)
        );

        // Test zero fiat amount
        request.fiatAmount = 0;
        vm.expectRevert(FulfillmentRequestLib.InvalidFiatAmount.selector);
        testHelper.validateRequestHelper{value: weiAmount}(
            serviceID,
            request,
            address(registry)
        );
    }

    function test_validateERC20Request(
        uint256 serviceID,
        uint256 tokenAmount,
        uint256 fiatAmount,
        string memory serviceRef
    ) public {
        tokenAmount = bound(tokenAmount, 1, 1000000e18);
        fiatAmount = bound(fiatAmount, 1, 1000000);

        ERC20FulFillmentRequest memory request = ERC20FulFillmentRequest({
            payer: msg.sender,
            tokenAmount: tokenAmount,
            fiatAmount: fiatAmount,
            serviceRef: serviceRef,
            token: address(token)
        });

        Service memory service = Service({
            serviceId: serviceID,
            beneficiary: payable(address(0x123)),
            feeAmount: tokenAmount / 10,
            fulfiller: payable(address(0x456))
        });

        registry.setService(serviceID, service);
        registry.setRefValid(serviceID, serviceRef, true);
        tokenRegistry.setWhitelisted(address(token), true);

        Service memory returnedService = testHelper.validateERC20RequestHelper(
            serviceID,
            request,
            address(registry),
            address(tokenRegistry)
        );

        assertEq(returnedService.serviceId, service.serviceId);
    }

    function test_validateERC20Request_EdgeCases(
    uint256 serviceID,
    uint256 tokenAmount,
    uint256 fiatAmount,
    string memory serviceRef,
    address invalidToken
) public {
    // Test max uint256 values
    tokenAmount = type(uint256).max;
    fiatAmount = type(uint256).max;
    
    ERC20FulFillmentRequest memory request = ERC20FulFillmentRequest({
        payer: msg.sender,
        tokenAmount: tokenAmount,
        fiatAmount: fiatAmount,
        serviceRef: serviceRef,
        token: address(token)
    });

    // Test with invalid token address
    vm.assume(invalidToken != address(0) && !tokenRegistry.isTokenWhitelisted(invalidToken));
    request.token = invalidToken;
    vm.expectRevert(abi.encodeWithSelector(
        FulfillmentRequestLib.UnsupportedToken.selector,
        invalidToken
    ));
    testHelper.validateERC20RequestHelper(
        serviceID,
        request,
        address(registry),
        address(tokenRegistry)
    );
}

function test_validateERC20Request_InvalidRef(
    uint256 serviceID,
    uint256 tokenAmount,
    uint256 fiatAmount,
    string memory serviceRef
) public {
    vm.assume(tokenAmount > 0 && tokenAmount < type(uint256).max);
    vm.assume(fiatAmount > 0);

    ERC20FulFillmentRequest memory request = ERC20FulFillmentRequest({
        payer: msg.sender,
        tokenAmount: tokenAmount,
        fiatAmount: fiatAmount,
        serviceRef: serviceRef,
        token: address(token)
    });

    Service memory service = Service({
        serviceId: serviceID,
        beneficiary: payable(address(0x123)),
        feeAmount: tokenAmount / 10,
        fulfiller: payable(address(0x456))
    });

    registry.setService(serviceID, service);
    registry.setRefValid(serviceID, serviceRef, false); // Invalid ref
    tokenRegistry.setWhitelisted(address(token), true);

    vm.expectRevert(FulfillmentRequestLib.InvalidRef.selector);
    testHelper.validateERC20RequestHelper(
        serviceID,
        request,
        address(registry),
        address(tokenRegistry)
    );
}

function test_validateRequest_ZeroAddressCases(
    uint256 serviceID,
    uint256 weiAmount,
    uint256 fiatAmount,
    string memory serviceRef
) public {
    weiAmount = bound(weiAmount, 1, 100 ether);
    fiatAmount = bound(fiatAmount, 1, 1000000);

    FulFillmentRequest memory request = FulFillmentRequest({
        payer: address(0), // Zero address payer
        weiAmount: weiAmount,
        fiatAmount: fiatAmount,
        serviceRef: serviceRef
    });

    Service memory service = Service({
        serviceId: serviceID,
        beneficiary: payable(address(0)), // Zero address beneficiary
        feeAmount: 100,
        fulfiller: payable(address(0)) // Zero address fulfiller
    });

    registry.setService(serviceID, service);
    registry.setRefValid(serviceID, serviceRef, true);

    vm.deal(address(testHelper), weiAmount + service.feeAmount);
    
    // Test should still pass as library doesn't validate addresses
    testHelper.validateRequestHelper{value: weiAmount + service.feeAmount}(
        serviceID,
        request,
        address(registry)
    );
}

function test_validateERC20Request_EmptyStrings(
    uint256 serviceID,
    uint256 tokenAmount,
    uint256 fiatAmount
) public {
    vm.assume(tokenAmount > 0 && tokenAmount < type(uint256).max);
    vm.assume(fiatAmount > 0);

    ERC20FulFillmentRequest memory request = ERC20FulFillmentRequest({
        payer: msg.sender,
        tokenAmount: tokenAmount,
        fiatAmount: fiatAmount,
        serviceRef: "", // Empty string
        token: address(token)
    });

    Service memory service = Service({
        serviceId: serviceID,
        beneficiary: payable(address(0x123)),
        feeAmount: tokenAmount / 10,
        fulfiller: payable(address(0x456))
    });

    registry.setService(serviceID, service);
    registry.setRefValid(serviceID, "", true); // Allow empty string
    tokenRegistry.setWhitelisted(address(token), true);

    // Test with empty string reference
    Service memory returnedService = testHelper.validateERC20RequestHelper(
        serviceID,
        request,
        address(registry),
        address(tokenRegistry)
    );
    assertEq(returnedService.serviceId, service.serviceId);
}

}

// Mock Contracts
contract MockFulfillableRegistry {
    mapping(uint256 => Service) public services;
    mapping(uint256 => mapping(string => bool)) public validRefs;

    function setService(uint256 serviceId, Service memory service) public {
        services[serviceId] = service;
    }

    function setRefValid(uint256 serviceId, string memory ref, bool valid) public {
        validRefs[serviceId][ref] = valid;
    }

    function getService(uint256 serviceId) public view returns (Service memory) {
        return services[serviceId];
    }

    function isRefValid(uint256 serviceId, string memory ref) public view returns (bool) {
        return validRefs[serviceId][ref];
    }
}

contract MockTokenRegistry {
    mapping(address => bool) public whitelisted;

    function setWhitelisted(address token, bool status) public {
        whitelisted[token] = status;
    }

    function isTokenWhitelisted(address token) public view returns (bool) {
        return whitelisted[token];
    }
}

contract MockERC20 is ERC20 {
    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function mint(address to, uint256 amount) public {
        _mint(to, amount);
    }
}