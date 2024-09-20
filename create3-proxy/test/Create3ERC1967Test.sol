// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../src/Create3ERC1967.sol";
import "./TestImplementation.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract Create3ERC1967Test is Test {
    function testDeployImplementation() public {
        bytes32 salt = keccak256("test_implementation");
        bytes memory creationCode = type(TestImplementation).creationCode;

        address impl = Create3ERC1967._deployImplementation(salt, creationCode);

        assertTrue(impl != address(0), "Implementation should be deployed");
        assertTrue(impl.code.length > 0, "Implementation should have code");
    }

    function testDeployProxy() public {
        bytes32 salt = keccak256("test_proxy");
        bytes memory creationCode = type(TestImplementation).creationCode;
        uint256 initialValue = 42;
        bytes memory initializerData = abi.encodeWithSignature("initialize(uint256)", initialValue);

        address proxy = Create3ERC1967.deploy(salt, creationCode, initializerData);

        assertTrue(proxy != address(0), "Proxy should be deployed");
        assertTrue(proxy.code.length > 0, "Proxy should have code");

        TestImplementation impl = TestImplementation(proxy);
        assertEq(impl.value(), initialValue, "Proxy should be initialized with correct value");
    }

    function testProxyFunctionality() public {
        bytes32 salt = keccak256("test_proxy_functionality");
        bytes memory creationCode = type(TestImplementation).creationCode;
        uint256 initialValue = 42;
        bytes memory initializerData = abi.encodeWithSignature("initialize(uint256)", initialValue);

        address proxy = Create3ERC1967.deploy(salt, creationCode, initializerData);
        TestImplementation impl = TestImplementation(proxy);

        uint256 newValue = 100;
        impl.setValue(newValue);
        assertEq(impl.value(), newValue, "Proxy should update value correctly");
    }

    function testDeterministicAddresses() public {
        bytes32 salt = keccak256("test_deterministic");
        bytes memory creationCode = type(TestImplementation).creationCode;
        bytes memory initializerData = abi.encodeWithSignature("initialize(uint256)", 42);

        address proxy1 = Create3ERC1967.deploy(salt, creationCode, initializerData);
        
        vm.roll(block.number + 1);  // Move to next block
        
        address proxy2 = Create3ERC1967.deploy(salt, creationCode, initializerData);

        assertEq(proxy1, proxy2, "Proxies should have the same address");
    }

    function testRevertOnRedeployment() public {
        bytes32 salt = keccak256("test_revert_redeploy");
        bytes memory creationCode = type(TestImplementation).creationCode;
        bytes memory initializerData = abi.encodeWithSignature("initialize(uint256)", 42);

        Create3ERC1967.deploy(salt, creationCode, initializerData);

        vm.expectRevert();
        Create3ERC1967.deploy(salt, creationCode, initializerData);
    }
}
