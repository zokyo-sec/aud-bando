//SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract DemoToken is ERC20 {
    constructor() ERC20("DEMOTOKEN", "DMT") public {
        _mint(msg.sender, 10000000000000000 * (10 ** decimals()));
    }
}
