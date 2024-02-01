// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import './IFulfillableRegistry.sol';
import './ITukyFulfillable.sol';
import './TukyFulfillableV1.sol';

/**
 * @title TukyFulfillmentManager
 * 
 * This contract manages services and fulfillables for the Tuky protocol.
 * It inherits from OwnableUpgradeable and UUPSUpgradeable contracts.
 * 
 * OwnableUpgradeable provides basic access control functionality, 
 * where only the contract owner can perform certain actions.
 * 
 * UUPSUpgradeable enables the contract to be upgraded without 
 * losing its state, allowing for seamless upgrades of the 
 * contract's implementation logic.
 * 
 * The purpose pf this contract is to interact with the FulfillableRegistry
 * and the TukyFulfillable contracts to perform the following actions:
 * 
 * - Set up a service escrow address and validator address.
 * - Register a fulfillment result for a service.
 * - Withdraw a refund from a service.
 * - Withdraw funds for a beneficiary in a releasable pool.
 * 
 * The owner of the contract is the operator of the fulfillment protocol.
 * But the fulfillers are the only ones that can register a fulfillment result 
 * and withdraw a refund.
 * 
 */
contract TukyFulfillmentManagerV1 is OwnableUpgradeable, UUPSUpgradeable {

    address private _serviceRegistry;

    event ServiceAdded(uint256 serviceID, address escrow, address validator, address fulfiller);

    function initialize(address serviceRegistry) public virtual initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        _serviceRegistry = serviceRegistry;
    }

    // UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}


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
        address fulfiller,
        address router
    ) 
        public 
        virtual
        onlyOwner 
        returns (address[2] memory) 
    {
        require(serviceID > 0, "Service ID is invalid");
        require(address(validator) != address(0), "Validator address is required.");
        TukyFulfillableV1 _escrow = new TukyFulfillableV1(beneficiaryAddress, serviceID, feeAmount, msg.sender, router, fulfiller);
        _escrow.setFee(feeAmount);
        IFulfillableRegistry(_serviceRegistry).addService(serviceID, Service({
            serviceId: serviceID,
            contractAddress: address(_escrow),
            fulfiller: fulfiller,
            validator: validator,
            feeAmount: feeAmount
        }));
        emit ServiceAdded(serviceID, address(_escrow), validator, fulfiller);
        return [address(_escrow), validator];
    }

    /**
     * @dev withdrawRefund
     * This method must only be called by the service fulfiller
     */
    function withdrawRefund(uint256 serviceID, address payable refundee) public virtual {
        Service memory service = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        require(
            service.fulfiller == msg.sender, 
            "Only the fulfiller can withdraw the refund"
        );
        require(ITukyFulfillable(service.contractAddress).withdrawRefund(refundee), "Withdrawal failed");
    }

    /**
     * @dev registerFulfillment
     * This method must only be called by the service fulfiller.
     * It registers a fulfillment result for a service.
     * @param serviceID 
     * @param fulfillment 
     */
    function registerFulfillment(uint256 serviceID, FulFillmentResult memory fulfillment) public virtual {
        Service memory service = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        require(
            service.fulfiller == msg.sender, 
            "Only the fulfiller can register a fulfillment"
        );
        ITukyFulfillable(service.contractAddress).registerFulfillment(fulfillment);
    }
}