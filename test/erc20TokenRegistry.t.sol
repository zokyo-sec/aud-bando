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
import {ERC20TokenRegistry} from '../contracts/periphery/registry/ERC20TokenRegistry.sol';


contract ERC20TokenRegistryTest is Test {

    ERC20TokenRegistry public erc20_registry;
    
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
        address registry_implementation = address(new ERC20TokenRegistry());

        bytes memory data = abi.encodeCall(ERC20TokenRegistry.initialize, ());
        address registry_proxy = address(new ERC1967Proxy(registry_implementation, data));
        _registryProxy = registry_proxy;
        _registryImplementation = registry_implementation;

        erc20_registry = ERC20TokenRegistry(_registryProxy);
    }

    function test_nothing_coin() public {
        console.log("Just typing here...");
    }

    function test_addToken(address _token) public {
        vm.assume(_token != address(0));
        erc20_registry.addToken(_token);
        bool result = erc20_registry.isTokenWhitelisted(_token);
        assertEq(result, true);
    }

    function test_addTokenReverts(address _token) public {
        vm.expectRevert();
        erc20_registry.addToken(address(0));

        // Unathorized role calling add token
        vm.prank(alice);
        vm.expectRevert();
        erc20_registry.addToken(_token);
    }

    function test_addTokenRevertsWhenAlreadyAdded(address _token) public {
        vm.assume(_token != address(0));
        erc20_registry.addToken(_token);
        vm.expectRevert();
        erc20_registry.addToken(_token);
    }

    function test_removeToken(address _token) public {
        vm.assume(_token != address(0));
        erc20_registry.addToken(_token);
        erc20_registry.removeToken(_token);

        // Unathorized role calling add token
        erc20_registry.addToken(_token);
        vm.prank(alice);
        vm.expectRevert();
        erc20_registry.removeToken(_token);
    }




    

}