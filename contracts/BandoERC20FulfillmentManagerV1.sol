// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import '@openzeppelin/contracts/access/Ownable.sol';
import './periphery/registry/IFulfillableRegistry.sol';
import './IBandoERC20Fulfillable.sol';
import './BandoERC20FulfillableV1.sol';
import './FulfillmentTypes.sol';

/**
 * @title BandoFulfillmentManager
 * 
 * This contract manages services and fulfillables for the Bando protocol.
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
 * and the BandoFulfillable contracts to perform the following actions:
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
contract BandoERC20FulfillmentManagerV1 is Ownable {

    address private _serviceRegistry;

    address private _escrow;

    event ServiceAdded(uint256 serviceID, address escrow, address fulfiller);

    constructor(address serviceRegistry, address escrow) Ownable(msg.sender) {
        _serviceRegistry = serviceRegistry;
        _escrow = escrow;
    }

    /**
     * @dev withdrawRefund
     * This method must only be called by the service fulfiller or the owner.
     * @param serviceID uint256 service identifier
     * @param refundee address payable address of the refund recipient
     */
    function withdrawERC20Refund(uint256 serviceID, address token, address refundee) public virtual {
        Service memory service = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller) {
            require(msg.sender == owner(), "Only the fulfiller or the owner can withdraw a refund");
        }
        require(IBandoERC20Fulfillable(_escrow).withdrawERC20Refund(token, refundee), "Withdrawal failed");
    }

    /**
     * @dev registerFulfillment
     * This method must only be called by the service fulfiller or the owner
     * It registers a fulfillment result for a service calling the escrow contract.
     * @param serviceID uint256 service identifier
     * @param fulfillment the fullfilment result
     */
    function registerFulfillment(uint256 serviceID, FulFillmentResult memory fulfillment) public virtual {
        Service memory service = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller) {
            require(msg.sender == owner(), "Only the fulfiller or the owner can register a fulfillment");
        }
        IBandoERC20Fulfillable(_escrow).registerFulfillment(fulfillment);
    }
}
