// SPDX-License-Identifier: ISC
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/proxy/Proxy.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @notice This is the upgradable proxy contract that delegates Anvil protocol governance logic to the implementation,
 * providing a consistent governor address along with upgradability.
 */
// solc-ignore-next-line missing-receive
contract AnvilGovernorDelegator is Proxy, Ownable {
    /***************
     * ERROR TYPES *
     ***************/
    error InvalidImplementationAddress(address _implementation);

    /**********
     * EVENTS *
     **********/

    /// Emitted when the delegate pointed to by this proxy is updated from `oldImplementation` to `newImplementation`.
    event NewImplementation(address oldImplementation, address newImplementation);

    /******************
     * CONTRACT STATE *
     ******************/

    /// The address of the implementation to which this proxy points.
    address public implementation;

    /*************
     * FUNCTIONS *
     *************/

    constructor(
        address timelock_,
        address governanceToken_,
        address implementation_,
        uint votingPeriod_,
        uint votingDelay_,
        uint proposalThreshold_
    ) Ownable(msg.sender) {
        /*** Initialize implementation ***/
        bytes memory initializeCalldata = abi.encodeWithSignature(
            "initialize(address,address,uint32,uint48,uint256)",
            timelock_,
            governanceToken_,
            votingPeriod_,
            votingDelay_,
            proposalThreshold_
        );

        (bool success, bytes memory returnData) = implementation_.delegatecall(initializeCalldata);
        assembly {
            if eq(success, 0) {
                revert(add(returnData, 0x20), returndatasize())
            }
        }

        /*** Set proxy implementation ***/
        _setImplementation(implementation_);
    }

    /**
     * @notice Called by the admin to update the implementation of the delegator.
     * @param implementation_ The address of the new implementation for delegation.
     */
    function _setImplementation(address implementation_) public onlyOwner {
        if (implementation_ == address(0)) {
            revert InvalidImplementationAddress(implementation_);
        }

        address oldImplementation = implementation;
        implementation = implementation_;

        emit NewImplementation(oldImplementation, implementation);
    }

    /**
     * @inheritdoc Proxy
     */
    function _implementation() internal view override(Proxy) returns (address) {
        return implementation;
    }
}
