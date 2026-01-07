// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";

/// @title DiamondTimelock
/// @notice Timelock controller for Diamond Dividend Vault governance
/// @dev Wraps OpenZeppelin TimelockController with preset configuration
contract DiamondTimelock is TimelockController {
    /// @notice Minimum delay for timelock execution (2 days)
    uint256 public constant MIN_DELAY = 2 days;

    /// @notice Initialize the timelock
    /// @param proposers Addresses that can schedule operations (typically the Governor)
    /// @param executors Addresses that can execute operations (typically anyone or Governor)
    /// @param admin Optional admin address (use address(0) to disable)
    constructor(
        address[] memory proposers,
        address[] memory executors,
        address admin
    ) TimelockController(MIN_DELAY, proposers, executors, admin) {}
}
