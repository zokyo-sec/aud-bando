// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "@openzeppelin/contracts/utils/Create2.sol";

contract Create3ERC1967 {
    // Event emitted when a new proxy is deployed
    event ProxyDeployed(address indexed proxy, bytes32 salt);

    // Deploys an ERC1967 proxy using Create3 pattern
    function deployProxy(
        address create3_factory,
        bytes32 salt,
        bytes memory creationCode,
        bytes memory initializerData
    ) public returns (address) {
        //deploy the implementation
        address implementation = _deployImplementation(create3_factory, salt, creationCode);

        // Generate the initialization code for the ERC1967Proxy
        bytes memory initCode = abi.encodePacked(
            type(ERC1967Proxy).creationCode,
            abi.encode(implementation, initializerData)
        );

        address proxy = ICREATE3Factory(create3_factory).deploy(salt, initCode);

        emit ProxyDeployed(proxy, salt);
        return proxy;
    }

    function _deployImplementation(address create3_factory, bytes32 salt, bytes memory creationCode) internal returns (address) {
        return ICREATE3Factory(create3_factory).deploy(salt, creationCode);
    }

    // Computes the address where a proxy would be deployed
    function computeProxyAddress(bytes32 salt) public view returns (address) {
        return Create2.computeAddress(
            salt,
            keccak256(abi.encodePacked(
                type(ERC1967Proxy).creationCode,
                abi.encode(address(0), "") // Dummy values, as they don't affect the address computation
            )),
            address(this)
        );
    }
}
