// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import "./FulfillmentTypes.sol";

/**
* @dev Interface for bando fulfillment protocol ERC20 support escrow.
* This interface is intented to be implemented by any contract that wants to be a fulfillable.
* It is the same a the BandoFulfillable interface but for ERC20 transfers.
* A fulfillable is a contract that can accept fulfillments from a router.
* The router will route fulfillments to the fulfillable based on the serviceID.
*/
interface IBandoERC20Fulfillable {
    function depositERC20(ERC20FulFillmentRequest memory request) external;

    function setERC20Fee(address token, uint256 amount) external;

    function registerFulfillment(FulFillmentResult memory fulfillment) external returns (bool);

    function serviceID() external view returns (uint256);

    function fulfiller() external view returns (address);

    function recordsOf(address payer) external view returns (uint256[] memory);

    function record(uint256 id) external view returns (ERC20FulFillmentRecord memory);

    function withdrawERC20Refund(address token, address refundee) external returns (bool);
}
