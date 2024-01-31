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


/**
 * ----- TukyRouter -----
 * This Smart Contract is intented to be user-facing.
 * Any valid address can request a fulfillment to a valid fulfillable.
 * -----------------------
 */
contract TukyRouterV1 is 
    Initializable,
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable {
    using Address for address payable;
    using Math for uint256;

    TukyFulfillableV1 private _escrow;
    mapping(uint256 => address) private _services;
    mapping(uint256 => address) private _validators;
    mapping(uint256 => address) private _fulfillers;

    event ServiceRequested(uint256 serviceID, FulFillmentRequest request);
    event RefValidationFailed(uint256 serviceID, string serviceRef);
    event ServiceAdded(uint256 serviceID, address escrow, address validator, address fulfiller);
  
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
        uint256 feeAmount,
        address fulfiller
    ) 
        public 
        virtual
        onlyOwner 
        returns (address[2] memory) 
    {
        require(serviceID > 0, "Service ID is invalid");
        require(address(validator) != address(0), "Validator address is required.");
        _escrow = new TukyFulfillableV1(beneficiaryAddress, serviceID, feeAmount, fulfiller);
        ITukyFulfillable(_escrow).setFee(feeAmount);
        _services[serviceID] = address(_escrow);
        _validators[serviceID] = validator;
        _fulfillers[serviceID] = fulfiller;
        emit ServiceAdded(serviceID, _services[serviceID], validator, fulfiller);
        return [_services[serviceID], _validators[serviceID]];
    }
    
}
