// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * TODO: CREATE EXTENSIVE DOCUMENTATION ABOUT THE USAGE OF THIS CONTRACT AND ITS INTENTIONS
 * AND POSSIBLE ATTACK VECTORS
 * 
 * ----- TukiRouter -----
 * This Smart Contract is intented to be user-facing.
 * Any valid address can request a fulfillment to a valid fulfillable.
 * 
 * Pre-conditions:
 * 
 * - verified identifier
 * - valid fulfillable id
 * - enough balance on the sender account
 * 
 * 
 * Post-conditions:
 * 
 * - ServiceRequested Event emitted
 * - payment due is trasferred to escrow contract until fulfillment
 * 
 * -----------------------
 * 
 */
contract TukiRouterV1 is Initializable, OwnableUpgradeable {
    using AddressUpgradeable for address payable;
    using SafeMathUpgradeable for uint256;

    mapping(uint256 => address) private _services;

    event ServiceRequested(address indexed payer, uint256 weiAmount, bytes32 serviceRef, address escrowContract);
  
    /**
     * @dev Constructor.
     */
    function initialize() public virtual initializer {
        __Ownable_init();
    }

    /**
     * @return The current state of the escrow.
     */
    function requestService(address escrowContract, string calldata serviceRef) public payable returns (bool) {
        bytes32 ref = keccak256(abi.encodePacked(serviceRef));
        //TODO Validate reference
        //TODO validate amount with modifier
        //TODO validate enough balance on payer
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
