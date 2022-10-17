// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./TukiRouterV1.sol";

/**
 * Test upgrade on router
 */
contract RouterUpgradeTester is TukiRouterV1 {
    using AddressUpgradeable for address payable;
    using SafeMathUpgradeable for uint256;

    function isUpgrade() public view onlyOwner returns (bool) {
        return true;
    }
}
