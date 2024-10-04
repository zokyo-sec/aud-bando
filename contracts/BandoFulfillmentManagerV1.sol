// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol';
import './periphery/registry/IFulfillableRegistry.sol';
import './IBandoFulfillable.sol';
import './BandoERC20FulfillableV1.sol';
import './BandoFulfillableV1.sol';
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
contract BandoFulfillmentManagerV1 is OwnableUpgradeable, UUPSUpgradeable, ReentrancyGuardUpgradeable {

    address private _serviceRegistry;
    address private _escrow;
    address private _erc20_escrow;

    event ServiceAdded(uint256 serviceID, address escrow, address fulfiller);

    function initialize(address serviceRegistry, address escrow, address erc20Escrow) public virtual initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
        _serviceRegistry = serviceRegistry;
        _escrow = escrow;
        _erc20_escrow = erc20Escrow;
    }

    // UUPS upgrade authorization
    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}


    /**
     * @dev setService
     * This method must only be called by an owner.
     * It sets up a service escrow address and validator address.
     * 
     * The escrow is intended to be a valid Bando escrow contract
     * 
     * The validator address is intended to be a contract that validates the service's
     * identifier. eg. phone number, bill number, etc.
     * @return address[2]
     */
    function setService(
        uint256 serviceID,
        uint256 feeAmount,
        address fulfiller,
        address payable beneficiary
    ) 
        public
        virtual
        onlyOwner 
        returns (Service memory)
    {
        require(serviceID > 0, "Service ID is invalid");
        Service memory service = Service({
            serviceId: serviceID,
            fulfiller: fulfiller,
            feeAmount: feeAmount,
            releaseablePool: 0,
            beneficiary: beneficiary
        });
        IFulfillableRegistry(_serviceRegistry).addService(serviceID, service);
        emit ServiceAdded(serviceID, address(_escrow), fulfiller);
        return service;
    }

    /**
     * setServiceRef
     * 
     * This method must only be called by the owner.
     * It sets up a service reference for a service.
     * @param serviceID uint256 service identifier
     * @param serviceRef string service reference
     * @return bool
     */
    function setServiceRef(uint256 serviceID, string memory serviceRef) public virtual onlyOwner returns (string[] memory) {
        return IFulfillableRegistry(_serviceRegistry).addServiceRef(serviceID, serviceRef);
    }

    /**
     * @dev withdrawRefund
     * This method must only be called by the service fulfiller or the owner.
     * @param serviceID uint256 service identifier
     * @param refundee address payable address of the refund recipient
     */
    function withdrawRefund(uint256 serviceID, address payable refundee) public virtual {
        Service memory service = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller) {
            require(msg.sender == owner(), "Only the fulfiller or the owner can withdraw a refund");
        }
        require(IBandoFulfillable(_escrow).withdrawRefund(serviceID, refundee), "Withdrawal failed");
    }

    /**
     * @dev registerFulfillment
     * This method must only be called by the service fulfiller or the owner
     * It registers a fulfillment result for a service calling the escrow contract.
     * @param serviceID uint256 service identifier
     * @param fulfillment the fullfilment result
     */
    function registerFulfillment(uint256 serviceID, FulFillmentResult memory fulfillment) public virtual nonReentrant {
        Service memory service = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller) {
            require(msg.sender == owner(), "Only the fulfiller or the owner can withdraw a refund");
        }
        IBandoFulfillable(_escrow).registerFulfillment(serviceID, fulfillment);
    }

    /**
     * @dev withdrawRefund
     * This method must only be called by the service fulfiller or the owner.
     * @param serviceID uint256 service identifier
     * @param refundee address payable address of the refund recipient
     */
    function withdrawERC20Refund(uint256 serviceID, address token, address refundee) public virtual nonReentrant {
        Service memory service = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller) {
            require(msg.sender == owner(), "Only the fulfiller or the owner can withdraw a refund");
        }
        require(IBandoERC20Fulfillable(_escrow).withdrawERC20Refund(serviceID, token, refundee), "Withdrawal failed");
    }

    /**
     * @dev registerERC20Fulfillment
     * This method must only be called by the service fulfiller or the owner
     * It registers a fulfillment result for a service calling the escrow contract.
     * @param serviceID uint256 service identifier
     * @param fulfillment the fullfilment result
     */
    function registerERC20Fulfillment(uint256 serviceID, FulFillmentResult memory fulfillment) public virtual nonReentrant {
        Service memory service = IFulfillableRegistry(_serviceRegistry).getService(serviceID);
        if (msg.sender != service.fulfiller) {
            require(msg.sender == owner(), "Only the fulfiller or the owner can register a fulfillment");
        }
        IBandoERC20Fulfillable(_escrow).registerFulfillment(serviceID, fulfillment);
    }
}