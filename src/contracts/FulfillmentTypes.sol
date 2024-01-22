// SPDX-License-Identifier: MIT
// Inspired in:
// OpenZeppelin Contracts v4.4.1 (utils/escrow/Escrow.sol)

pragma solidity >=0.8.20 <0.9.0;
    
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