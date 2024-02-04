// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

contract ERC20TokenRegistry is OwnableUpgradeable, UUPSUpgradeable {
    mapping(address => bool) private whitelist;

    event TokenAdded(address indexed token);
    event TokenRemoved(address indexed token);

    function initialize() public initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    function isTokenWhitelisted(address token) public view returns (bool) {
        return whitelist[token];
    }

    function addToken(address token) public onlyOwner {
        require(token != address(0), "ERC20TokenRegistry: Token address cannot be zero");
        require(!whitelist[token], "ERC20TokenRegistry: Token already whitelisted");

        whitelist[token] = true;
        emit TokenAdded(token);
    }

    function removeToken(address token) public onlyOwner {
        require(whitelist[token], "ERC20TokenRegistry: Token not whitelisted");

        whitelist[token] = false;
        emit TokenRemoved(token);
    }
}
