// SPDX-License-Identifier: MIT
// OpenZeppelin Contracts v4.4.1 (utils/escrow/Escrow.sol)

pragma solidity 0.8.17;

import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/utils/structs/BitMaps.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";


/**
 * @title ToppiFulfillerV1
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
contract TukiFulfillerV1 is Initializable, OwnableUpgradeable {
    using Address for address payable;
    using SafeMath for uint256;

    event Deposit(address indexed payee, uint256 weiAmount);
    event Withdrawn(address indexed payee, uint256 weiAmount);
    event RefundRegistered(address refundee, uint256 amount);

    address payable private _beneficiary;
    mapping(address => uint256) private _deposits;
    mapping(address => uint256) private _refunds;
    uint256 private _serviceIdentifier;

    /**
     * @dev initializer.
     * @param beneficiary_ The beneficiary of the deposits.
     */
    function initialize(address payable beneficiary_, uint256 serviceIdentifier_) public virtual initializer {
        require(beneficiary_ != address(0), "ToppiEscrow: beneficiary is the zero address");
        _beneficiary = beneficiary_;
        _serviceIdentifier = serviceIdentifier_;
        _transferOwnership(msg.sender);
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
     * @return Total refunds for a payer
     */
    function refundsOf(address payee) public view returns (uint256) {
        return _refunds[payee];
    }

    /**
     * @dev Stores the sent amount as credit to be claimed.
     * @param payer The destination address of the funds.
     */
    function deposit(address payer) public payable virtual onlyOwner {
        uint256 amount = msg.value;
        _deposits[payer] = amount.add(_deposits[payer]);
        emit Deposit(payer, amount);
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
    function withdrawRefund(address payable refundee) public virtual {
        require(msg.sender == refundee, "Sender must be the same as the payee address.");
        uint256 payment = _refunds[refundee];
        _refunds[refundee] = 0;
        refundee.sendValue(payment); 
        emit Withdrawn(refundee, payment);
    }

    /**
     * @dev Allows for refunds to take place, rejecting further deposits.
     */
    function registerRefund(address payable refundee, uint256 amount) public virtual onlyOwner {
        // TODO: add logic for address based refunds
        _refunds[refundee] = amount.add(_refunds[refundee]);
        emit RefundRegistered(refundee, amount);
    }

    /**
     * @dev Withdraws the beneficiary's funds.
     */
    function beneficiaryWithdraw() public virtual {
        beneficiary().sendValue(address(this).balance);
    }
}
