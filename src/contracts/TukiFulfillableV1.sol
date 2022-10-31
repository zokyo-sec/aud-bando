// SPDX-License-Identifier: MIT
// Inspired in:
// OpenZeppelin Contracts v4.4.1 (utils/escrow/Escrow.sol)

pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";


/**
* enum with states for fulfillment results.
 */
enum FulFillmentResultState {
    FAILED,
    SUCCESS
}

/**
* @dev The fulfiller will accept FulfillmentResults submitted to it,
* and if valid, will persist them on-chain as FulfillmentRecords
*/
struct FulFillmentRecord {
    uint256 id; // auto-incremental, generated in contract
    address fulfiller;
    uint256 externalID; // id coming from the fulfiller as proof.
    address payer; // address of payer
    uint256 weiAmount; // address of the subject, the recipient of a successful verification
    uint256 feeAmount; // feeAmount charged in wei
    uint256 entryTime; // time at which the fulfillment was submitted
    string receiptURI; // the fulfillment external receipt uri.
}

/**
* @dev A fulfiller will submit a fulfillment result in this format.
*/
struct FulFillmentResult {
    uint256 id; // id coming from the fulfiller as proof.
    address fulfiller; //address of the fulfiller that initiated the rsult
    address payer; // address of payer
    uint256 weiAmount; // address of the subject, the recipient of a successful verification
    uint256 feeAmount; // feeAmount charged in wei
    string receiptURI; // the fulfillment external receipt uri. 
    FulFillmentResultState status;   
}

/**
* @dev Anybody can submit a fulfillment request through a router.
*/
struct FulFillmentRequest {
    address payer; // address of payer
    uint256 weiAmount; // address of the subject, the recipient of a successful verification
    uint256 fiatAmount; // fiat amount to be charged for the fufillable
    uint256 feeAmount; // fee amount in wei
    string serviceRef; // identifier required to route the payment to the user's destination
}

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
contract TukiFulfillableV1 is Ownable {
    using Address for address payable;
    using SafeMath for uint256;
    using Counters for Counters.Counter;

    /**********************/
    /* EVENT DECLARATIONS */
    /**********************/

    event DepositReceived(FulFillmentRequest request);
    event RefundWithdrawn(address indexed payee, uint256 weiAmount);
    event RefundAuthorized(address indexed payee, uint256 weiAmount);
    event LogFailure(string message);

    /*****************************/
    /* STATE VARIABLES           */
    /*****************************/

    //Auto-incrementable id storage
    Counters.Counter private _fulfillmentIds;

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

    /*****************************/
    /* FULFILLER LOGIC           */
    /*****************************/

    constructor(address payable beneficiary_, uint256 serviceIdentifier_)
    {
        require(address(beneficiary_) != address(0), "Beneficiary is the zero address");
        require(serviceIdentifier_ > 0, "Service ID is required");
        _beneficiary = beneficiary_;
        _serviceIdentifier = serviceIdentifier_;
    }

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
        uint256 refund_amount = _authorized_refunds[refundee];
        _authorized_refunds[refundee] = 0;
        _withdrawRefund(refundee, refund_amount);
    }

    /**
    * @dev internal function to withraw.
    * Should only be called when previously authorized.
    *
    * Will emit a RefundWithdrawn event on success.
    * 
    * @param refundee The address to send the value to.
    */
    function _withdrawRefund(address payable refundee, uint256 amount) internal onlyOwner {
        refundee.sendValue(amount); 
        emit RefundWithdrawn(refundee, amount);
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
     *
     * If the fulfillment has failed:
     * - a refund will be authorized for a later withdrawal.
     *
     * If these verifications pass:
     * - add the amount fulfilled to the release pool.
     * - substract the amount from the payer's deposits.
     * - persist this as a FulFillmentRecord to the blockchain.
     *
     * @param fulfillment the fulfillment result attached to it.
     */
    function registerFulfillment(FulFillmentResult memory fulfillment) public virtual onlyOwner {
        uint256 total_amount = fulfillment.weiAmount.add(fulfillment.feeAmount);
        require(_deposits[fulfillment.payer] >= total_amount, "There is not enough balance to be released.");
        if(fulfillment.status == FulFillmentResultState.FAILED) {
            _authorizeRefund(fulfillment.payer, total_amount);
        } else if(fulfillment.status != FulFillmentResultState.SUCCESS) {
            // something weird happened. must better log this.
            emit LogFailure("Fulfillment result was submitted with weird status");
            revert();
        } else {
            _releaseablePool = _releaseablePool.add(total_amount);
            _deposits[fulfillment.payer] = _deposits[fulfillment.payer].sub(total_amount);
            // create a FulfillmentRecord
            FulFillmentRecord memory fulfillmentRecord = FulFillmentRecord({
                id: 0,
                externalID: fulfillment.id,
                fulfiller: fulfillment.fulfiller,
                entryTime: block.timestamp,
                payer: fulfillment.payer,
                weiAmount: fulfillment.weiAmount,
                feeAmount: fulfillment.feeAmount, 
                receiptURI: fulfillment.receiptURI
            });
            _fulfillmentIds.increment();
            fulfillmentRecord.id = _fulfillmentIds.current();
            _fulfillmentRecordCount++;
            _fulfillmentRecords[fulfillmentRecord.id] = fulfillmentRecord;
            _fulfillmentRecordsForSubject[fulfillmentRecord.payer].push(fulfillmentRecord.id);
        }
    }

    /**
     * @dev Withdraws the beneficiary's available balance to release (fulfilled with success).
     */
    function beneficiaryWithdraw() public virtual {
        require(_releaseablePool > 0, "There is no balance to release.");
        _releaseablePool = 0;
        beneficiary().sendValue(_releaseablePool);
    }
}
