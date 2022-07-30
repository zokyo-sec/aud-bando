// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract ToppiRouterV1 is Ownable, Initializable {
    using Address for address payable;
    using SafeMath for uint256;

    mapping(uint256 => address) private _services;

    event ServiceRequested(address indexed payer, uint256 weiAmount, bytes32 serviceRef, address escrowContract);
  
    /**
     * @dev Constructor.
     */
    function initialize() public virtual initializer {
        _transferOwnership(msg.sender);
    }

    /**
     * @return The current state of the escrow.
     */
    function requestService(address escrowContract, string calldata serviceRef) public payable returns (bool) {
        bytes32 ref = keccak256(abi.encodePacked(serviceRef));
        //TODO route the payment to the corresponding escrow contract
        emit ServiceRequested(msg.sender, msg.value, ref, escrowContract);
        return true;
    }

    /**
     * @return the address for the service ID of a particular service.
     *
     */
    function serviceOf(uint256 serviceID) public view returns (address) {
        return _services[serviceID];
    }

    function setService(uint256 serviceID, address serviceEscrow) public virtual onlyOwner returns (bool) {
        _services[serviceID] = serviceEscrow;
        return true;
    }
}
