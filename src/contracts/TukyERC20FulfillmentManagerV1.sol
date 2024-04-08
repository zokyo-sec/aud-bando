// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import './periphery/registry/IFulfillableRegistry.sol';
import './ITukyERC20Fulfillable.sol';
import './TukyERC20FulfillableV1.sol';
import './FulfillmentTypes.sol';

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
contract TukyERC20FulfillmentManagerV1 is OwnableUpgradeable, UUPSUpgradeable {

    address private _serviceRegistry;

    event ServiceAdded(uint256 serviceID, address escrow, address fulfiller);

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
    function enableERC20Service(
        uint256 serviceID,
        address payable beneficiaryAddress,
        address fulfiller,
        address router
    ) 
        public 
        virtual
        onlyOwner 
        returns (address)
    {
        require(serviceID > 0, "Service ID is invalid");
        TukyERC20FulfillableV1 _escrow = new TukyERC20FulfillableV1(beneficiaryAddress, serviceID, router, fulfiller);
        IFulfillableRegistry(_serviceRegistry).enableERC20(serviceID, address(_escrow));
        return address(_escrow);
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
        require(ITukyERC20Fulfillable(service.erc20ContractAddress).withdrawERC20Refund(token, refundee), "Withdrawal failed");
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
            require(msg.sender == owner(), "Only the fulfiller or the owner can withdraw a refund");
        }
        ITukyERC20Fulfillable(service.erc20ContractAddress).registerFulfillment(fulfillment);
    }
}