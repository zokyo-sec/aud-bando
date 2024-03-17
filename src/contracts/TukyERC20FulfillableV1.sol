// SPDX-License-Identifier: MIT
// Inspired in:
// OpenZeppelin Contracts v4.4.1 (utils/escrow/Escrow.sol)

pragma solidity >=0.8.20 <0.9.0;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./ITukyERC20Fulfillable.sol";

/**
 * @title TukyERC20FulfillableV1
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
contract TukyERC20FulfillableV1 is ITukyERC20Fulfillable {
    using Address for address;
    using Math for uint256;

    /**********************/
    /* EVENT DECLARATIONS */
    /**********************/

    event DepositReceived(ERC20FulFillmentRecord record);
    event RefundWithdrawn(address token, address indexed payee, uint256 weiAmount);
    event RefundAuthorized(address indexed payee, uint256 weiAmount);
    event FeeUpdated(uint256 serviceID, uint256 amount);

    /*****************************/
    /* STATE VARIABLES           */
    /*****************************/

    //Auto-incrementable id storage
    uint256 private _fulfillmentIdCount;

    // All fulfillment records keyed by their ids
    mapping(uint256 => ERC20FulFillmentRecord) private _fulfillmentRecords;

    // Deposits mapped to subject addresses
    mapping(address => uint256[]) private _fulfillmentRecordsForSubject;

    // Total deposits registered
    uint256 private _fulfillmentRecordCount;

    // The beneficiary address of the contract which will receive released funds.
    address payable private _beneficiary;

    // The fulfiller address
    address private _fulfiller;

    // The protocol manager address
    address private _manager;

    // The protocol router address
    address private _router;

    // The deposits and refunds in escrow per token per payer
    mapping(address => mapping(address => uint256)) private _deposits;
    mapping(address => mapping(address => uint256)) private _authorized_refunds;

    //The Service Identifier to its corresponding Fulfillable product
    uint256 private _serviceIdentifier;

    //The Fee Amounts per token to its corresponding Fulfillable product in wei.
    mapping(address => uint256) _feeAmounts;

    // The amounts per token that is available to be released by the beneficiary.
    mapping(address => uint256) private _releaseablePools;

    /*****************************/
    /* FULFILLABLE ESCROW LOGIC  */
    /*****************************/

    constructor(
        address payable beneficiary_,
        uint256 serviceIdentifier_,
        address router_,
        address fulfiller_
    ) {
        require(address(beneficiary_) != address(0), "Beneficiary is the zero address");
        require(serviceIdentifier_ > 0, "Service ID is required");
        _beneficiary = beneficiary_;
        _serviceIdentifier = serviceIdentifier_;
        _fulfiller = fulfiller_;
        _manager = msg.sender;
        _router = router_;
        _fulfillmentIdCount = 1;
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
     * @return Total deposits from a payer per token
     */
    function depositsOf(address token, address payer) public view returns (uint256) {
        return _deposits[token][payer];
    }

    /**
     * @dev fulfiller of the escrow.
     * @return the fulfiller address
     */
    function fulfiller() public view virtual returns (address) {
        return _fulfiller;
    }

    /**
     * recordsOf
     * @dev Returns the fulfillment records for a given payer.
     * @param payer the address of the payer
     */
    function recordsOf(address payer) public view returns (uint256[] memory) {
        return _fulfillmentRecordsForSubject[payer];
    }

    /**
     * @dev Returns the fulfillment record for a given id.
     * @param id the id of the record
     */
    function record(uint256 id) public view returns (ERC20FulFillmentRecord memory) {
        return _fulfillmentRecords[id];
    }

    /**
     * @dev Stores the sent amount as credit to be claimed.
     * @param fulfillmentRequest The fulfillment record to be stored.
     * 
     */
    function depositERC20(ERC20FulFillmentRequest memory fulfillmentRequest) public virtual {
        require(_router == msg.sender, "Caller is not the router");
        uint256 amount = fulfillmentRequest.tokenAmount;
        address token = fulfillmentRequest.token;
        // check for deposits on that token

        (bool success, uint256 result) = amount.tryAdd(_deposits[token][fulfillmentRequest.payer]);
        require(success, "Overflow while adding deposits");
        // transfer the ERC20 token to this contract
        require(
            IERC20(fulfillmentRequest.token).transferFrom(
                fulfillmentRequest.payer,
                address(this),
                amount
            ),
            "ERC20 Transfer failed"
        );
        _deposits[token][fulfillmentRequest.payer] = result;
        // create a FulfillmentRecord
        ERC20FulFillmentRecord memory fulfillmentRecord = ERC20FulFillmentRecord({
            id: _fulfillmentIdCount,
            serviceRef: fulfillmentRequest.serviceRef,
            externalID: "",
            fulfiller: _fulfiller,
            entryTime: block.timestamp,
            payer: fulfillmentRequest.payer,
            tokenAmount: fulfillmentRequest.tokenAmount,
            feeAmount: _feeAmounts[fulfillmentRequest.token],
            fiatAmount: fulfillmentRequest.fiatAmount,
            receiptURI: "",
            status: FulFillmentResultState.PENDING,
            token: fulfillmentRequest.token
        });
        _fulfillmentIdCount += 1;
        _fulfillmentRecordCount += 1;
        _fulfillmentRecords[fulfillmentRecord.id] = fulfillmentRecord;
        _fulfillmentRecordsForSubject[fulfillmentRecord.payer].push(fulfillmentRecord.id);
        emit DepositReceived(fulfillmentRecord);
    }

    /**
     * @dev Refund accumulated balance for a refundee, forwarding all gas to the
     * recipient.
     *
     * WARNING: Forwarding all gas opens the door to reentrancy vulnerabilities.
     * Make sure you trust the recipient, or are either following the
     * checks-effects-interactions pattern or using {ReentrancyGuard}.
     *
     * @param token The address of the ERC20 token.
     * @param refundee The address whose funds will be withdrawn and transferred to.
     */
    function withdrawERC20Refund(address token, address refundee) public virtual returns (bool) {
        require(_manager == msg.sender, "Caller is not the manager");
        require(_authorized_refunds[token][refundee] > 0, "Address is not allowed any refunds");
        uint256 refund_amount = _authorized_refunds[token][refundee];
        _withdrawRefund(token, refundee, refund_amount);
        _authorized_refunds[token][refundee] = 0;
        return true;
    }

    /**
     * @dev Set the beneficiary fee.
     * @param token The address of the token.
     * @param amount The destination address of the funds.
     */
    function setERC20Fee(address token, uint256 amount) public virtual {
        require(_manager == msg.sender, "Caller is not the manager");
        _feeAmounts[token] = amount;
        emit FeeUpdated(_serviceIdentifier, amount);
    }

    /**
    * @dev internal function to withraw.
    * Should only be called when previously authorized.
    *
    * Will emit a RefundWithdrawn event on success.
    * 
    * @param token The address of the token.
    * @param refundee The address to send the value to.
    */
    function _withdrawRefund(address token, address refundee, uint256 amount) internal {
        require(
            IERC20(token).transfer(refundee, amount),
            "ERC20 Transfer failed"
        );
        emit RefundWithdrawn(token, refundee, amount);
    }

    /**
     * @dev Allows for refunds to take place.
     * 
     * This function will authorize a refund for a later withdrawal.
     * 
     * @param token the token to be refunded.
     * @param refundee the record to be
     * @param amount the amount to be authorized.
     */
    function _authorizeRefund(address token, address refundee, uint256 amount) internal {
        (bool asuccess, uint256 addResult) = _authorized_refunds[token][refundee].tryAdd(amount);
        require(asuccess, "Overflow while adding authorized refunds");
        uint256 total_refunds = addResult;
        require(
            _deposits[token][refundee] >= amount,
            "Token Amount is bigger than the total in escrow"
        );
        require(
            _deposits[token][refundee] >= total_refunds,
            "Total token refunds would be bigger than the total in escrow"
        );
        (bool ssuccess, uint256 subResult) = _deposits[token][refundee].trySub(amount);
        require(ssuccess, "Overflow while substracting deposits");
        _deposits[token][refundee] = subResult;
        _authorized_refunds[token][refundee] = total_refunds;
        emit RefundAuthorized(refundee, amount);
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
     * - update the FulFillmentRecord to the blockchain.
     *
     * @param fulfillment the fulfillment result attached to it.
     */
    function registerFulfillment(FulFillmentResult memory fulfillment) public virtual returns (bool) {
        require(_manager == msg.sender, "Caller is not the manager");
        require(_fulfillmentRecords[fulfillment.id].id > 0, "Fulfillment record does not exist");
        require(_fulfillmentRecords[fulfillment.id].status == FulFillmentResultState.PENDING, "Fulfillment already registered");
        address token = _fulfillmentRecords[fulfillment.id].token;
        (bool ffsuccess, uint256 total_amount) = _fulfillmentRecords[fulfillment.id].tokenAmount.tryAdd(
            _feeAmounts[token]
        );
        require(ffsuccess, "Overflow while adding fulfillment amount and fee");
        require(_deposits[token][_fulfillmentRecords[fulfillment.id].payer] >= total_amount, "There is not enough balance to be released");
        if(fulfillment.status == FulFillmentResultState.FAILED) {
            _authorizeRefund(token, _fulfillmentRecords[fulfillment.id].payer, total_amount);
            _fulfillmentRecords[fulfillment.id].status = fulfillment.status;
        } else if(fulfillment.status != FulFillmentResultState.SUCCESS) {
            revert('Unexpected status');
        } else {
            (bool rlsuccess, uint256 releaseResult) = _releaseablePools[token].tryAdd(total_amount);
            require(rlsuccess, "Overflow while adding to releaseable pool");
            (bool dsuccess, uint256 subResult) = _deposits[token][_fulfillmentRecords[fulfillment.id].payer].trySub(total_amount);
            require(dsuccess, "Overflow while substracting from deposits");
            _releaseablePools[token] = releaseResult;
            _deposits[token][_fulfillmentRecords[fulfillment.id].payer] = subResult;
            _fulfillmentRecords[fulfillment.id].receiptURI = fulfillment.receiptURI;
            _fulfillmentRecords[fulfillment.id].status = fulfillment.status;
            _fulfillmentRecords[fulfillment.id].externalID = fulfillment.externalID;
        }
        return true;
    }

    /**
     * @dev Withdraws the beneficiary's available balance to release (fulfilled with success).
     * Only the fulfiller of the service can withdraw the releaseable pool.
     */
    function beneficiaryWithdraw(address token) public virtual {
        require(_manager == msg.sender, "Caller is not the manager");
        require(_releaseablePools[token] > 0, "There is no balance to release.");
        _releaseablePools[token] = 0;
        require(
            IERC20(token).transfer(_beneficiary, _releaseablePools[token]),
            "ERC20 Transfer failed"
        );
    }
}
