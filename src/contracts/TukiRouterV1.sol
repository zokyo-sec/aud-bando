// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IIdentifierValidator.sol";
import "./TukiFulFillableV1.sol";


/**
 * ----- TukiRouter -----
 * This Smart Contract is intented to be user-facing.
 * Any valid address can request a fulfillment to a valid fulfillable.
 * -----------------------
 */
contract TukiRouterV1 is Initializable, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using AddressUpgradeable for address payable;
    using SafeMathUpgradeable for uint256;

    mapping(uint256 => TukiFulfillableV1) private _services;
    mapping(uint256 => address) private _validators;

    event ServiceRequested(
        uint256 serviceID,
        FulFillmentRequest request
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
     * requestService
     * @return true if amount was transferred to the escrow.
     * Pre-conditions:
     * 
     * - verified identifier
     * - valid fulfillable id
     * - valid IIdentifierValidator contract
     * - positive amount
     * - positive fiat amount in precision 2
     * - enough balance on the sender account
     * 
     * 
     * Post-conditions:
     * 
     * - DepositReceived Event emitted
     * - payment due is trasferred to escrow contract until fulfillment
     */
    function requestService(uint256 serviceID, FulFillmentRequest memory request) 
        public 
        payable
        whenNotPaused
        returns (bool)
    {
        uint256 total_amount = request.weiAmount.add(request.feeAmount);
        require(total_amount >= 0, "Amount is invalid");
        require(request.fiatAmount >= 0, "Fiat amount is invalid");
        require(total_amount == msg.value, "Fee and wei amount dont match value");
        require(address(_services[serviceID]) != address(0), "Service ID is not supported");
        require(address(_validators[serviceID]) != address(0), "Validator not found for service ID");
        require(
            IIdentifierValidator(_validators[serviceID]).matches(request.serviceRef),
            "The service identifier failed to validate"
        );
        _services[serviceID].deposit{value: msg.value}(request);
        return true;
    }

    /**
     * @return the address for the service ID of a particular service.
     *
     */
    function serviceOf(uint256 serviceID) public view returns (address[2] memory) {
        require(address(_services[serviceID]) != address(0), "Service ID is not supported.");
        require(address(_validators[serviceID]) != address(0), "Validator not found for service ID.");
        return [address(_services[serviceID]), _validators[serviceID]];
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
    function setService(
        uint256 serviceID,
        address validator,
        address payable beneficiary
    ) 
        public 
        virtual 
        onlyOwner 
        returns (address[2] memory) 
    {
        require(serviceID > 0, "Service ID is invalid");
        require(address(validator) != address(0), "Validator address is required");
        TukiFulfillableV1 escrow = new TukiFulfillableV1(beneficiary, serviceID);
        _services[serviceID] = escrow;
        _validators[serviceID] = validator;
        address escrowAddress = address(_services[serviceID]);
        emit ServiceAdded(serviceID, escrowAddress, validator);
        return [escrowAddress, _validators[serviceID]];
    }
}
