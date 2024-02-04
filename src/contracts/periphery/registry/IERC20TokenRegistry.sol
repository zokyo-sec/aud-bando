// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

/**
 * @title IERC20TokenRegistry
 * @author Tuky
 * @notice Interface for ERC20 token registry
 * @dev This contract is used to whitelist ERC20 tokens
 */
interface IERC20TokenRegistry {
    function isTokenWhitelisted(address token) external view returns (bool);
    function addToken(address token) external;
    function removeToken(address token) external;
}
