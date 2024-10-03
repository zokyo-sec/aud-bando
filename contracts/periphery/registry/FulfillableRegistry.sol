// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import './IFulfillableRegistry.sol';

/// @title FulfillableRegistry
/// @author g6s
/// @notice A registry for fulfillable services
/// @dev This contract is upgradeable, Ownable, and uses UUPSUpgradeable
contract FulfillableRegistry is IFulfillableRegistry, UUPSUpgradeable, OwnableUpgradeable {

    // Mapping to store services by their ID
    mapping(uint256 => Service) private _serviceRegistry;

    /// Mapping to store service references by service ID
    /// @dev serviceID => (index => reference)
    mapping(uint256 => mapping(uint256 => string)) private _serviceRefs;

    /// Mapping to store the count of references for each service
    /// @dev serviceID => reference count
    mapping(uint256 => uint256) private _serviceRefCount;

    /// Mapping to store fulfillers and their associated services
    /// @dev fulfiller => (serviceId => exists)
    mapping(address => mapping(uint256 => bool)) private _fulfillerServices;
    /// @dev fulfiller => service count
    mapping(address => uint256) private _fulfillerServiceCount;

    /// Mapping to store native coin refunds and deposit amounts
    /// @dev serviceID => userAddress => depositedAmount
    mapping(
        uint256 => mapping(address => uint256)
    ) private _deposits;
    /// @dev serviceID => userAddress => refundableAmount
    mapping(
        uint256 => mapping(address => uint256)
    ) private _authorized_refunds;

    /// Mapping to store erc20 refunds and deposit amounts
    /// @dev serviceID => tokenAddress => userAddress => depositedAmount
    mapping(
        uint256 => mapping(address => mapping(address => uint256))
    ) private _erc20_deposits;
    /// @dev serviceID => tokenAddress => userAddress => refundableAmount
    mapping(
        uint256 => mapping(address => mapping(address => uint256))
    ) private _erc20_authorized_refunds;

    uint256 _serviceCount;

    event ServiceRemoved(uint256 serviceID);

    function initialize() public virtual initializer {
        __Ownable_init(msg.sender);
        __UUPSUpgradeable_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    /**
     * addService
     * This method must only be called by the owner.
     * @param serviceId the service identifier
     * @param service the service info object
     */
    function addService(uint256 serviceId, Service memory service) external returns (bool) {
        require(
            _serviceRegistry[serviceId].fulfiller == address(0), 
            'FulfillableRegistry: Service already exists'
        );
        _serviceRegistry[serviceId] = service;
        return true;
    }

    /**
     * @notice updateServiceBeneficiary
     * @dev Updates the beneficiary of a service.
     * @param serviceId the service identifier
     * @param newBeneficiary the new beneficiary address
     */
    function updateServiceBeneficiary(uint256 serviceId, address payable newBeneficiary) external onlyOwner {
        require(_serviceRegistry[serviceId].fulfiller != address(0), 'FulfillableRegistry: Service does not exist');
        _serviceRegistry[serviceId].beneficiary = newBeneficiary;
    }

    /**
     * @notice updateServiceFeeAmount
     * @dev Updates the fee amount of a service.
     * @param serviceId the service identifier
     * @param newFeeAmount the new fee amount
     */
    function updateServiceFeeAmount(uint256 serviceId, uint256 newFeeAmount) external onlyOwner {
        require(_serviceRegistry[serviceId].fulfiller != address(0), 'FulfillableRegistry: Service does not exist');
        _serviceRegistry[serviceId].feeAmount = newFeeAmount;
    }

    /**
     * @notice updateServiceReleaseablePool
     * @dev Updates the releaseable pool of a service.
     * @param serviceId the service identifier
     * @param newReleaseablePool the new releaseable pool amount
     */
    function updateServiceReleaseablePool(uint256 serviceId, uint256 newReleaseablePool) external {
        require(_serviceRegistry[serviceId].fulfiller != address(0), 'FulfillableRegistry: Service does not exist');
        _serviceRegistry[serviceId].releaseablePool = newReleaseablePool;
    }

    /**
     * @notice updateServiceFulfiller
     * @dev Updates the fulfiller of a service.
     * @param serviceId the service identifier
     * @param newFulfiller the new fulfiller address
     */
    function updateServiceFulfiller(uint256 serviceId, address newFulfiller) external onlyOwner {
        require(_serviceRegistry[serviceId].fulfiller != address(0), 'FulfillableRegistry: Service does not exist');
        _serviceRegistry[serviceId].fulfiller = newFulfiller;
    }

    /**
     * addFulfiller
     * @param fulfiller the address of the fulfiller
     */
    function addFulfiller(address fulfiller, uint256 serviceID) external onlyOwner {
        require(!_fulfillerServices[fulfiller][serviceID], "Service already registered for this fulfiller");
        _fulfillerServices[fulfiller][serviceID] = true; // Associate the service ID with the fulfiller
        _fulfillerServiceCount[fulfiller]++; // Increment the service count for the fulfiller
    }

    /**
     * getService
     * @param serviceId the service identifier
     * @return the service info object
     */
    function getService(uint256 serviceId) external view returns (Service memory) {
        require(
            _serviceRegistry[serviceId].fulfiller != address(0), 
            'FulfillableRegistry: Service does not exist'
        );
        return _serviceRegistry[serviceId];
    }

    /**
     * removeServiceAddress
     * @param serviceId the service identifier
     */
    function removeServiceAddress(uint256 serviceId) external onlyOwner {
        delete _serviceRegistry[serviceId];
        _serviceCount--;
        emit ServiceRemoved(serviceId);
    }

    /**
     * addServiceRef
     * 
     * @param serviceId the service identifier
     * @param ref the reference to the service
     */
    function addServiceRef(uint256 serviceId, string memory ref) external returns (string[] memory) {
        require(_serviceRegistry[serviceId].fulfiller != address(0), "Service does not exist");
        uint256 refCount = _serviceRefCount[serviceId];
        _serviceRefs[serviceId][refCount] = ref; // Store the reference at the current index
        _serviceRefCount[serviceId]++; // Increment the reference count
    }

    /**
     * isRefValid
     * 
     * @param serviceId the service identifier
     * @param ref the reference to the service
     * @return true if the reference is valid
     */
    function isRefValid(uint256 serviceId, string memory ref) external view returns (bool) {
        uint256 refCount = _serviceRefCount[serviceId];
        for (uint256 i = 0; i < refCount; i++) {
            if (keccak256(abi.encodePacked(_serviceRefs[serviceId][i])) == keccak256(abi.encodePacked(ref))) {
                return true;
            }
        }
        return false;
    }

    function getDepositsFor(address payer, uint256 serviceID) external view returns (uint256 amount) {
        amount = _deposits[serviceID][payer];
    }

    function setDepositsFor(address payer, uint256 serviceID, uint256 amount) external {
        _deposits[serviceID][payer] = amount;
    }

    function getRefundsFor(address payer, uint256 serviceID) external view returns (uint256 amount) {
        amount = _authorized_refunds[serviceID][payer];
    }

    function setRefundsFor(address payer, uint256 serviceID, uint256 amount) external {
        _authorized_refunds[serviceID][payer] = amount;
    }

    // Function to check if a fulfiller can fulfill a service
    function canFulfillerFulfill(address fulfiller, uint256 serviceId) external view returns (bool) {
        return _fulfillerServices[fulfiller][serviceId];
    }
}
