// SPDX-License-Identifier: ISC
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/governance/TimelockControllerUpgradeable.sol";

/**
 * @notice Vanilla OpenZeppelin TimelockControllerUpgradeable implementation.
 */
contract AnvilTimelock is TimelockControllerUpgradeable {
    function initialize(
        uint256 minDelay,
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) external initializer {
        __TimelockController_init(minDelay, proposers, executors, admin);
    }
}
