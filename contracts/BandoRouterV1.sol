// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./IBandoFulfillable.sol";
import "./periphery/registry/IFulfillableRegistry.sol";
import { FulFillmentRequest } from "./FulfillmentTypes.sol";
import { FulfillmentRequestLib } from './libraries/FulfillmentRequestLib.sol';


/**
 * ----- BandoRouterV1 -----
 * This Smart Contract is intented to be user-facing.
 * Any valid address can request a fulfillment to a valid fulfillable.
 * 
 * The contract will validate the request and transfer the payment to the fulfillable contract.
 * 
 * -----------------------
 */
contract BandoRouterV1 is 
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable {

    address private _fulfillableRegistry;
    
    event ServiceRequested(uint256 serviceID, FulFillmentRequest request);

    /**
     * @dev Constructor.
     */
    function initialize(address serviceRegistry) public virtual initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _fulfillableRegistry = serviceRegistry;
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
     * - payment due is transferred to escrow contract until fulfillment
     */
    function requestService(
        uint256 serviceID,
        FulFillmentRequest memory request
    ) public payable whenNotPaused nonReentrant returns (bool) {
        //Validate request
        Service memory service = FulfillmentRequestLib.validateRequest(serviceID, request, _fulfillableRegistry);

        // Handle fee transfer here

        // Call the deposit function on the fulfillable contract
        //IBandoFulfillable(service.contractAddress).deposit{value: request.weiAmount}(request);

        emit ServiceRequested(serviceID, request);
        return true;
    }

}
