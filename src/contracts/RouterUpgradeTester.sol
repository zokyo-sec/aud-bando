// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "./TukiRouterV1.sol";

/**
 * Test upgrade on router
 */
contract RouterUpgradeTester is TukiRouterV1 {
    using Address for address payable;
    using Math for uint256;

    function isUpgrade() public view onlyOwner returns (bool) {
        return true;
    }
}
