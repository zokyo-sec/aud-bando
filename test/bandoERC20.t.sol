// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test, console} from "forge-std/Test.sol";
import {BandoERC20FulfillableV1} from "../contracts/BandoERC20FulfillableV1.sol";

// import {Upgrades} from "@openzeppelin-foundry-upgrades/Upgrades.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";


contract BandoERC20FulfillableV1Test is Test {

    BandoERC20FulfillableV1 public bandoERC20;
    
    address public _multiSigAddr;

    address public bob = address(0x23);
    address public alice = address(0x55);
    address _proxy;
    address _implementation;
    address owner;
    address _withdrawSigner;
    address _initialMintTo;

    function setUp() public {
        _multiSigAddr = address(0x22);
        _initialMintTo = address(0x23);
        _withdrawSigner = address(0x44);
        address implementation = address(new BandoERC20FulfillableV1());

        bytes memory data = abi.encodeCall(BandoERC20FulfillableV1.initialize, ());
        address proxy = address(new ERC1967Proxy(implementation, data));
        _proxy = proxy;
        _implementation = implementation;
        owner = _multiSigAddr;

        bandoERC20 = BandoERC20FulfillableV1(proxy);
        
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
}