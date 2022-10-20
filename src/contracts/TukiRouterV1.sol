// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IRegexValidator.sol";

/**
 * 
 * ----- TukiRouter -----
 * This Smart Contract is intented to be user-facing.
 * Any valid address can request a fulfillment to a valid fulfillable.
 * 
 * Pre-conditions:
 * 
 * - verified identifier
 * - valid fulfillable id
 * - positive amount
 * - positive fiat amount in precision 2
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
contract TukiRouterV1 is Initializable, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using AddressUpgradeable for address payable;
    using SafeMathUpgradeable for uint256;

    mapping(uint256 => address) private _services;
    mapping(uint256 => address) private _validators;

    event ServiceRequested(
        address indexed payer,
        uint256 weiAmount,
        bytes32 serviceRef,
        uint256 serviceID,
        uint256 fiatAmout
    );
    event RefValidationFailed(uint256 serviceID, string serviceRef);
    event ServiceAdded(uint256 serviceID, address escrow, address validator);
  
    /**
     * @dev Constructor.
     */
    function initialize() public virtual initializer {
        __Ownable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    /**
     * @dev required for UUPS upgrades
     **/
    function _authorizeUpgrade(address newImplementation)
        internal
        onlyOwner
        override
    {}

    /**
     * @return The current state of the escrow.
     */
    function requestService(
            uint256 serviceID, 
            string memory serviceRef,
            bool isERC20,
            address tokenAddress,
            uint256 fiatAmount
        ) 
        public 
        payable
        whenNotPaused
        returns (bool)
    {
        require(address(_services[serviceID]) != address(0), "Service ID is not supported");
        require(address(_validators[serviceID]) != address(0), "Validator not found for service ID");
        require(msg.value > 0, "Amount must be greater than zero");
        require(address(this).balance > msg.value, "Sender address has insufficient funds");
        bool isValidRef = IRegexValidator(_validators[serviceID]).matches(serviceRef);
        if(!isValidRef) {
            emit RefValidationFailed(serviceID, serviceRef);
            revert("The service identifier failed to validate");
        }
        bytes32 ref = keccak256(abi.encodePacked(serviceRef));
        //TODO route the payment to the corresponding escrow contract
        emit ServiceRequested(msg.sender, msg.value, ref, serviceID, fiatAmount);
        return true;
    }

    /**
     * @return the address for the service ID of a particular service.
     *
     */
    function serviceOf(uint256 serviceID) public view returns (address[2] memory) {
        require(address(_services[serviceID]) != address(0), "Service ID is not supported.");
        require(address(_validators[serviceID]) != address(0), "Validator not found for service ID.");
        return [_services[serviceID], _validators[serviceID]];
    }

    /**
     * @dev setService
     * This method must only be called by an owner.
     * It sets up a service escrow address and validator address.
     * 
     * The escrow is intended to be a valid tuki escrow contract
     * 
     * The validator address is intended to be a contract that validates the service's
     * identifier. eg. phone number, bill number, etc.
     * @return address[2]
     */
    function setService(uint256 serviceID, address serviceEscrow, address validator) 
        public 
        virtual 
        onlyOwner 
        returns (address[2] memory) 
    {
        require(serviceID > 0, "Service ID is invalid");
        require(address(serviceEscrow) != address(0), "Service escrow is required");
        require(address(validator) != address(0), "Validator address is required");
        _services[serviceID] = serviceEscrow;
        _validators[serviceID] = validator;
        emit ServiceAdded(serviceID, serviceEscrow, validator);
        return [_services[serviceID], _validators[serviceID]];
    }
}
