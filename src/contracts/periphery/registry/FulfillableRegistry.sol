// SPDX-License-Identifier: MIT
pragma solidity >=0.8.20 <0.9.0;

import '@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol';
import '@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol';
import './IFulfillableRegistry.sol';

/**
 * @title FulfillableRegistry
 * @author g6s
 * @notice This contract is intented to be used as a registry for fulfillable services.
 * It will store the address of the contract that implements the fulfillable service.
 * The address can be retrieved by the serviceId.
 * @dev This contract is upgradeable.
 * @dev This contract is Ownable.
 * @dev This contract uses UUPSUpgradeable.
 * 
 */
contract FulfillableRegistry is IFulfillableRegistry, UUPSUpgradeable, OwnableUpgradeable {

    mapping(uint256 => Service) private _serviceRegistry;

    mapping(uint256 => string[]) private _serviceRefs;

    mapping(address => Service[]) private _fulfillers;

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
            _serviceRegistry[serviceId].contractAddress == address(0), 
            'FulfillableRegistry: Service already exists'
        );
        _serviceRegistry[serviceId] = service;
        _fulfillers[service.fulfiller].push(service);
        _serviceCount++;
        return true;
    }

    /**
     * addFulfiller
     * @param fulfiller the address of the fulfiller
     */
    function addFulfiller(address fulfiller) external onlyOwner {
        _fulfillers[fulfiller].push();
    }

    /**
     * getService
     * @param serviceId the service identifier
     * @return the service info object
     */
    function getService(uint256 serviceId) external view returns (Service memory) {
        require(
            _serviceRegistry[serviceId].contractAddress != address(0), 
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
        _serviceRefs[serviceId].push(ref);
        return _serviceRefs[serviceId];
    }

    /**
     * isRefValid
     * 
     * @param serviceId the service identifier
     * @param ref the reference to the service
     * @return true if the reference is valid
     */
    function isRefValid(uint256 serviceId, string memory ref) external view returns (bool) {
        string[] memory refs = _serviceRefs[serviceId];
        for (uint256 i = 0; i < refs.length; i++) {
            if (keccak256(abi.encodePacked(refs[i])) == keccak256(abi.encodePacked(ref))) {
                return true;
            }
        }
        return false;
    }
}
