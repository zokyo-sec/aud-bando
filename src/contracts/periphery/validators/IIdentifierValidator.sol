// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

interface IIdentifierValidator {
    function matches(string memory input) external pure returns (bool);
}
