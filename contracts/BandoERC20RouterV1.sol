// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "./IBandoERC20Fulfillable.sol";
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

    event ServiceRequested(uint256 serviceID, ERC20FulFillmentRequest request);
    event RefValidationFailed(uint256 serviceID, string serviceRef);
  
    /**
     * @dev Constructor.
     */
    function initialize(address serviceRegistry, address tokenRegistry) public virtual initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
        __ReentrancyGuard_init();
        _fulfillableRegistry = serviceRegistry;
        _tokenRegistry = tokenRegistry;
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
        uint256 serviceID, ERC20FulFillmentRequest memory request) public payable whenNotPaused nonReentrant returns (bool)
    {
        Service memory service = FulfillmentRequestLib.validateRequest(serviceID, request, _fulfillableRegistry);
        IBandoERC20Fulfillable(service.erc20ContractAddress).depositERC20(request);
        emit ServiceRequested(serviceID, request);
        return true;
    }
    
}
