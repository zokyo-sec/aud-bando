// SPDX-License-Identifier: MIT
// Inspired in:
// OpenZeppelin Contracts v4.4.1 (utils/escrow/Escrow.sol)

pragma solidity 0.8.17;

import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/security/PausableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/AddressUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/CountersUpgradeable.sol";
import "./ITukiFulfillableV1.sol";

/**
 * @title TukiFulfillableV1
 * @dev Base escrow contract, holds funds designated for a beneficiary until they
 * withdraw them or a refund is emitted.
 *
 * Intended usage: This contract (and derived escrow contracts) should be a
 * standalone contract, that only interacts with the contract that instantiated
 * it. That way, it is guaranteed that all Ether will be handled according to
 * the `Escrow` rules, and there is no need to check for payable functions or
 * transfers in the inheritance tree. The contract that uses the escrow as its
 * payment method should be its owner, and provide public methods redirecting
 * to the escrow's deposit and withdraw.
 */
contract TukiFulfillableV1 is Initializable, OwnableUpgradeable, UUPSUpgradeable, ITukiFulfillableV1 {
    using AddressUpgradeable for address payable;
    using SafeMathUpgradeable for uint256;
    using CountersUpgradeable for CountersUpgradeable.Counter;

    //Auto-incrementable id storage
    CountersUpgradeable.Counter private _fulfillmentIds;

    // All fulfillment records keyed by their ids
    mapping(uint256 => FulFillmentRecord) private _fulfillmentRecords;

    // Deposits mapped to subject addresses
    mapping(address => uint256[]) private _fulfillmentRecordsForSubject;

    // Total deposits registered
    uint256 private _fulfillmentRecordCount;

    // The beneficiary address of the contract which will receive released funds.
    address payable private _beneficiary;

    mapping(address => uint256) private _deposits;
    mapping(address => uint256) private _authorized_refunds;

    //The Service Identifier to its corresponding Fulfillable product
    uint256 private _serviceIdentifier;

    // The amount that is available to be released by the beneficiary.
    uint256 _releaseablePool;

    /**
     * @dev initializer.
     * @param beneficiary_ The beneficiary of the deposits.
     */
    function initialize(address payable beneficiary_, uint256 serviceIdentifier_) public virtual initializer {
        require(address(beneficiary_) != address(0), "Beneficiary is the zero address");
        require(serviceIdentifier_ > 0, "Service ID is required");
        _beneficiary = beneficiary_;
        _serviceIdentifier = serviceIdentifier_;
        __Ownable_init();
        __UUPSUpgradeable_init();
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
     * @return The beneficiary of the escrow.
     */
    function beneficiary() public view virtual returns (address payable) {
        return _beneficiary;
    }

    /**
     * @return The service ID of the escrow.
     */
    function serviceID() public view virtual returns (uint256) {
        return _serviceIdentifier;
    }

    /**
     * @return Total deposits from a payer
     */
    function depositsOf(address payer) public view returns (uint256) {
        return _deposits[payer];
    }

    /**
     * @dev Stores the sent amount as credit to be claimed.
     * @param fulfillmentRequest The destination address of the funds.
     */
    function deposit(FulFillmentRequest memory fulfillmentRequest) public payable virtual onlyOwner {
        uint256 amount = msg.value;
        _deposits[fulfillmentRequest.payer] = amount.add(_deposits[fulfillmentRequest.payer]);
        emit DepositReceived(fulfillmentRequest);
    }

    /**
     * @dev Refund accumulated balance for a refundee, forwarding all gas to the
     * recipient.
     *
     * WARNING: Forwarding all gas opens the door to reentrancy vulnerabilities.
     * Make sure you trust the recipient, or are either following the
     * checks-effects-interactions pattern or using {ReentrancyGuard}.
     *
     * @param refundee The address whose funds will be withdrawn and transferred to.
     */
    function withdrawRefund(address payable refundee) public virtual onlyOwner {
        require(_authorized_refunds[refundee] > 0, "Address is not allowed any refunds");
        _authorized_refunds[refundee] = 0;
        _withdrawRefund(refundee);
    }

    /**
    * @dev internal function to withraw.
    * Should only be called when previously authorized.
    *
    * Will emit a RefundWithdrawn event on success.
    * 
    * @param refundee The address to send the value to.
    */
    function _withdrawRefund(address payable refundee) internal onlyOwner {
        refundee.sendValue(_authorized_refunds[refundee]); 
        emit RefundWithdrawn(refundee, _authorized_refunds[refundee]);
    }

    /**
     * @dev Allows for refunds to take place.
     * 
     * @param refundee the record to be
     * @param weiAmount the amount to be authorized.
     */
    function _authorizeRefund(address refundee, uint256 weiAmount) internal onlyOwner {
        uint256 total_refunds = _authorized_refunds[refundee].add(weiAmount);
        require(
            _deposits[refundee] >= weiAmount,
            "Amount is bigger than the total in escrow"
        );
        require(
            _deposits[refundee] >= total_refunds,
            "Total refunds would be bigger than the total in escrow"
        );
        _deposits[refundee] = _deposits[refundee].sub(weiAmount);
        _authorized_refunds[refundee] = total_refunds;
        emit RefundAuthorized(refundee, weiAmount);
    }

    /**
     * @dev The fulfiller registers a fulfillment.
     *
     * We need to verify the amount of the fulfillment is actually available to release.
     * Then we can enrich the result with an auto-incremental unique ID.
     * and the timestamp when the record get inserted.
     * After these verifications we can add the amount fulfilled to the release pool. 
     * THen we persist this as a FulFillmentRecord to the blockchain.
     *
     * @param fulfillment the fulfillment result attached to it.
     */
    function registerFulfillment(FulFillmentResult memory fulfillment) public virtual onlyOwner {
        require(_deposits[fulfillment.payer] >= fulfillment.weiAmount, "There is not enough balance to be released.");
        _validateFulfillmentResult(fulfillment);
        _releaseablePool = _releaseablePool.add(fulfillment.weiAmount);
    }

    /**
     * @dev Withdraws the beneficiary's available balance to release (fulfilled with success).
     */
    function beneficiaryWithdraw() public virtual {
        beneficiary().sendValue(_releaseablePool);
    }

    /**
     * @dev Validate a fulfillment result and return a record to be persisted.
     * 
     * @param fulfillmentResult FulfillmentResult coming from the contract submition.
     */
    function _validateFulfillmentResult(FulFillmentResult memory fulfillmentResult) internal {
        if(fulfillmentResult.status == FulFillmentResultState.FAILED) {
            _authorizeRefund(fulfillmentResult.payer, fulfillmentResult.weiAmount);
        } else if(fulfillmentResult.status != FulFillmentResultState.SUCCESS) {
            // something weird happened. must better log this.
            emit LogFailure("Fulfillment result was submitted with weird status");
            revert();
        } else {
            // create a FulfillmentRecord
            FulFillmentRecord memory fulfillmentRecord = FulFillmentRecord({
                id: 0,
                externalID: fulfillmentResult.id,
                fulfiller: fulfillmentResult.fulfiller,
                entryTime: block.timestamp,
                payer: fulfillmentResult.payer,
                weiAmount: fulfillmentResult.weiAmount,
                receiptURI: fulfillmentResult.receiptURI
            });
            _fulfillmentIds.increment();
            fulfillmentRecord.id = _fulfillmentIds.current();
            _persistVerificationRecord(fulfillmentRecord);
        }
    }

    /**
    * Persists the fulfillment record to the state variable and mapps it by payer address.
    */
    function _persistVerificationRecord(FulFillmentRecord memory record) internal {
        _fulfillmentRecordCount++;
        _fulfillmentRecords[record.id] = record;
        _fulfillmentRecordsForSubject[record.payer].push(record.id);
    }
}
