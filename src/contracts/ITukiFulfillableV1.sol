
// Inspired in:
// OpenZeppelin Contracts v4.4.1 (utils/escrow/Escrow.sol)
// CENTRE HQ verite/packages/contract/contracts/IVerificationRegistry.sol

/**
 * SPDX-License-Identifier: MIT
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */
pragma solidity ^0.8.17;

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
    bytes32 serviceRef; // identifier required to route the payment to the user's destination
}

/**
* @dev Interface defining basic functionality for the Fulfillable Contract
 */
interface ITukiFulfillableV1 {

    /**********************/
    /* EVENT DECLARATIONS */
    /**********************/

    event DepositReceived(FulFillmentRequest request);
    event RefundWithdrawn(address indexed payee, uint256 weiAmount);
    event RefundAuthorized(address indexed payee, uint256 weiAmount);
    event LogFailure(string message);

    /*****************************/
    /* FULFILLER LOGIC           */
    /*****************************/

    /**
     * @return The beneficiary of the escrow.
     */
    function beneficiary() external view returns (address payable);
    /**
     * @return The service ID of the escrow.
     */
    function serviceID() external view returns (uint256);

    /**
     * @return Total deposits from a payer
     */
    function depositsOf(address payer) external view returns (uint256);

    /**
     * @dev Stores the sent amount as credit to be claimed.
     * @param fulfillmentRequest The destination address of the funds.
     */
    function deposit(FulFillmentRequest memory fulfillmentRequest) external payable;

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
    function withdrawRefund(address payable refundee) external;

    /**
     * @dev Allows for refunds to take place.
     *
     * @param refundee the address authorized for refunds
     * @param weiAmount the amount to be refunded if authorized.
     */
    //function authorizeRefund(address refundee, uint256 weiAmount) external;

    /**
     * @dev The fulfiller registers a fulfillment.
     *
     * @param fulfillment the fulfillment result attached to it.
     */
    function registerFulfillment(FulFillmentResult memory fulfillment) external;

    /**
     * @dev Withdraws the beneficiary's funds.
     */
    function beneficiaryWithdraw() external;
}