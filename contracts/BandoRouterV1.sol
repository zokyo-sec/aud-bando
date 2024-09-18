// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "./IBandoFulfillable.sol";
import "./periphery/registry/IFulfillableRegistry.sol";
import "./FulfillmentTypes.sol";


/**
 * ----- BandoRouter -----
 * This Smart Contract is intented to be user-facing.
 * Any valid address can request a fulfillment to a valid fulfillable.
 * 
 * The contract will validate the request and transfer the payment to the fulfillable contract.
 * -----------------------
 */

contract BandoRouterV1 is 
    OwnableUpgradeable,
    PausableUpgradeable,
    UUPSUpgradeable {

    using Address for address payable;
    using Math for uint256;

    address private _fulfillableRegistry;

    event ServiceRequested(uint256 serviceID, FulFillmentRequest request);
    event RefValidationFailed(uint256 serviceID, string serviceRef);
  
    /**
     * @dev Constructor.
     */
    function initialize(address serviceRegistry) public virtual initializer {
        __Ownable_init(msg.sender);
        __Pausable_init();
        __UUPSUpgradeable_init();
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
        uint256 serviceID, FulFillmentRequest memory request) public payable whenNotPaused returns (bool)
    {
        require(msg.value > 0, "Amount must be greater than zero");
        require(request.fiatAmount > 0, "Fiat amount is invalid");
        Service memory service = IFulfillableRegistry(_fulfillableRegistry).getService(serviceID);
        require(
            IFulfillableRegistry(_fulfillableRegistry).isRefValid(serviceID, request.serviceRef),
            "ref not in registry"
        );
        (bool success, uint256 total_amount) = request.weiAmount.tryAdd(service.feeAmount);
        require(success, "Overflow while adding fee and amount");
        require(msg.value == total_amount, "Transaction total does not match fee + amount.");
        IBandoFulfillable(service.contractAddress).deposit{value: msg.value}(request);
        emit ServiceRequested(serviceID, request);
        return true;
    }
    
}
