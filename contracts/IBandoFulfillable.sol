// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "./FulfillmentTypes.sol";

/**
* @dev Interface for bando fulfillment protocol escrow.
* This interface is intented to be implemented by any contract that wants to be a fulfillable.
* A fulfillable is a contract that can accept fulfillments from a router.
* The router will route fulfillments to the fulfillable based on the serviceID.
*/
interface IBandoFulfillable {
    function deposit(FulFillmentRequest memory request) external payable;

    function setFee(uint256 amount) external;

    function registerFulfillment(FulFillmentResult memory fulfillment) external returns (bool);

    function serviceID() external view returns (uint256);

    function fulfiller() external view returns (address);

    function recordsOf(address payer) external view returns (uint256[] memory);

    function record(uint256 id) external view returns (FulFillmentRecord memory);

    function withdrawRefund(address payable refundee) external returns (bool);
}
