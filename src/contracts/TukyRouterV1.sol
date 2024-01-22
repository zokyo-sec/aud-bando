// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./IIdentifierValidator.sol";
import "./ITukyFulfillable.sol";
import "./TukyFulfillableV1.sol";
import "hardhat/console.sol";


/**
 * ----- TukyRouter -----
 * This Smart Contract is intented to be user-facing.
 * Any valid address can request a fulfillment to a valid fulfillable.
 * -----------------------
 */
contract TukyRouterV1 is Initializable, OwnableUpgradeable, PausableUpgradeable, UUPSUpgradeable {
    using Address for address payable;
    using Math for uint256;

    TukyFulfillableV1 private _escrow;
    mapping(uint256 => address) private _services;
    mapping(uint256 => address) private _validators;

    event ServiceRequested(uint256 serviceID, FulFillmentRequest request);
    event RefValidationFailed(uint256 serviceID, string serviceRef);
    event ServiceAdded(uint256 serviceID, address escrow, address validator);
  
    /**
     * @dev Constructor.
     */
    function initialize() public virtual initializer {
        __Ownable_init(msg.sender);
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
     * - DepositReceived Event emitted by the underlying contract.
     * - payment due is trasferred to escrow contract until fulfillment
     */
    function requestService(
        uint256 serviceID, FulFillmentRequest memory request) public payable whenNotPaused returns (bool)
    {
        require(msg.value > 0, "Amount must be greater than zero");
        require(request.fiatAmount > 0, "Fiat amount is invalid");
        require(address(_services[serviceID]) != address(0), "Service ID is not supported");
        require(address(_validators[serviceID]) != address(0), "Validator not found for service ID");
        (bool success, uint256 total_amount) = request.weiAmount.tryAdd(ITukyFulfillable(_services[serviceID]).feeAmount());
        require(success, "Overflow while adding fee and amount");
        require(msg.value == total_amount, "Transaction total does not match fee + amount.");
        require(
            IIdentifierValidator(_validators[serviceID]).matches(request.serviceRef),
            "The service identifier failed to validate"
        );
        ITukyFulfillable(_services[serviceID]).deposit{value: msg.value}(request);
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
     * @return the fee amount for the service ID of a particular service.
     *
     */
    function feeOf(uint256 serviceID) public view returns (uint256) {
        require(address(_services[serviceID]) != address(0), "Service ID is not supported.");
        return ITukyFulfillable(_services[serviceID]).feeAmount();
    }

    /**
     * @dev setService
     * This method must only be called by an owner.
     * It sets up a service escrow address and validator address.
     * 
     * The escrow is intended to be a valid Tuky escrow contract
     * 
     * The validator address is intended to be a contract that validates the service's
     * identifier. eg. phone number, bill number, etc.
     * @return address[2]
     */
    function setService(
        uint256 serviceID,
        address payable beneficiaryAddress,
        address validator,
        uint256 feeAmount
    ) 
        public 
        virtual 
        onlyOwner 
        returns (address[2] memory) 
    {
        require(serviceID > 0, "Service ID is invalid");
        require(address(validator) != address(0), "Validator address is required");
        _escrow = new TukyFulfillableV1(beneficiaryAddress, serviceID, feeAmount);
        _services[serviceID] = address(_escrow);
        _validators[serviceID] = validator;
        emit ServiceAdded(serviceID, _services[serviceID], validator);
        return [_services[serviceID], _validators[serviceID]];
    }

    /**
    * @dev setFee
    * Sets the fee for a valid escrow contract
    * 
    * emits a FeeUpdated event from the underlying escrow contract.
    * @return uint256
    */
    function setFee(uint256 serviceID, uint256 feeAmount) public virtual onlyOwner returns (uint256) {
        require(serviceID > 0, "Service ID is invalid");
        require(feeAmount >= 0, "Fee Amount is invalid");
        ITukyFulfillable(_services[serviceID]).setFee(feeAmount);
        return feeAmount;
    }
    
}
