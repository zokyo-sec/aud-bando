// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IIdentifierValidator {
    function matches(string memory input) external pure returns (bool);
}
