// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./IBandoERC20Fulfillable.sol";
import "./IBandoFulfillable.sol";
import "./periphery/registry/IFulfillableRegistry.sol";
import "./FulfillmentTypes.sol";
import "./libraries/FulfillmentRequestLib.sol";


/**
 * ----- BandoERC20RouterV1 -----
 * This Smart Contract is intented to be user-facing.
 * Any valid address can request a fulfillment to a valid fulfillable.
 * 
 * The contract will validate the request and transfer the payment to the fulfillable contract.
 * -----------------------
 */
contract BandoERC20RouterV1 is 
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable,
    ReentrancyGuardUpgradeable {

    using Address for address payable;
    using Math for uint256;

    address private _fulfillableRegistry;
    address private _tokenRegistry;
    address payable private _escrow;
    address payable private _erc20Escrow;

    event ERC20ServiceRequested(uint256 serviceID, ERC20FulFillmentRequest request);
    event ServiceRequested(uint256 serviceID, FulFillmentRequest request);
    event RefValidationFailed(uint256 serviceID, string serviceRef);

    /**
     * @dev Constructor.
     */
    function initialize(
        address serviceRegistry,
        address tokenRegistry,
        address payable escrow,
        address payable erc20Escrow
    ) public virtual initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _fulfillableRegistry = serviceRegistry;
        _tokenRegistry = tokenRegistry;
        _escrow = escrow;
        _erc20Escrow = erc20Escrow;
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
     * requestERC20Service
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
    function requestERC20Service(
        uint256 serviceID, 
        ERC20FulFillmentRequest memory request
    ) public payable whenNotPaused nonReentrant returns (bool) {
        Service memory service = FulfillmentRequestLib.validateRequest(serviceID, request, _fulfillableRegistry);
        IBandoERC20Fulfillable(_erc20Escrow).depositERC20(request);
        emit ERC20ServiceRequested(serviceID, request);
        return true;
    }

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
        FulfillmentRequestLib.validateRequest(serviceID, request, _fulfillableRegistry);
        // Handle fee transfer here
        
        // Call the deposit function on the fulfillable contract
        IBandoFulfillable(_escrow).deposit{value: request.weiAmount}(serviceID, request);
        emit ServiceRequested(serviceID, request);
        return true;
    }
    
}
