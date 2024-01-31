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
 * The contract has a private variable _serviceRegistry of type address. 
 * This variable stores the address of the service registry.
 * 
 * The initialize function is used to initialize the contract's 
 * state variables. It sets the _serviceRegistry variable to its value.
 * 
 * The _authorizeUpgrade function is used to authorize upgrades 
 * to the contract's implementation. In this case, the function 
 * is empty, meaning that only the contract owner can authorize upgrades.
 * 
 * The setService function sets up a service by providing various 
 * parameters such as serviceID, beneficiaryAddress, validator, 
 * feeAmount, fulfiller, and router. This function is intended 
 * to be called only by the contract owner.
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
}