// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IAPYCalculator
/// @notice Interface for Diamond Dividend Vault APY calculations
/// @dev Provides on-chain yield estimation and historical tracking
interface IAPYCalculator {
    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Snapshot of yield metrics at a point in time
    struct YieldSnapshot {
        /// @notice Timestamp of the snapshot
        uint256 timestamp;
        /// @notice Total assets in vault at snapshot time
        uint256 totalAssets;
        /// @notice Total dividends distributed up to this point
        uint256 totalDividends;
        /// @notice Cumulative yield from all sources
        uint256 cumulativeYield;
    }

    /// @notice Breakdown of APY by source
    struct APYBreakdown {
        /// @notice Base APY from vault asset appreciation
        uint256 vaultAPY;
        /// @notice APY from dividend distributions
        uint256 dividendAPY;
        /// @notice Combined blended APY
        uint256 blendedAPY;
        /// @notice Timestamp of calculation
        uint256 calculatedAt;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a new yield snapshot is recorded
    event SnapshotRecorded(
        uint256 indexed snapshotId,
        uint256 timestamp,
        uint256 totalAssets,
        uint256 totalDividends
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // CORE APY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get the blended APY across all yield sources
    /// @dev Combines vault appreciation + dividend yield
    /// @return APY in basis points (10000 = 100%)
    function getBlendedAPY() external view returns (uint256);

    /// @notice Get effective APY for a specific user
    /// @dev Applies user's holding and balance multipliers
    /// @param account User address
    /// @return APY in basis points
    function getUserEffectiveAPY(address account) external view returns (uint256);

    /// @notice Get detailed APY breakdown
    /// @return breakdown Struct containing vault APY, dividend APY, and blended APY
    function getAPYBreakdown() external view returns (APYBreakdown memory breakdown);

    // ═══════════════════════════════════════════════════════════════════════════
    // PROJECTION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Estimate yield for a hypothetical deposit
    /// @param depositAmount Amount to simulate depositing
    /// @param holdingDays Number of days to project
    /// @return estimatedYield Projected yield in underlying asset terms
    function estimateYield(
        uint256 depositAmount,
        uint256 holdingDays
    ) external view returns (uint256 estimatedYield);

    /// @notice Estimate yield with user's current multipliers
    /// @param account User to calculate for
    /// @param additionalDays Additional days to project from now
    /// @return estimatedYield Projected yield in underlying asset terms
    function estimateUserYield(
        address account,
        uint256 additionalDays
    ) external view returns (uint256 estimatedYield);

    // ═══════════════════════════════════════════════════════════════════════════
    // SNAPSHOT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Record a new yield snapshot
    /// @dev Can be called by anyone, subject to minimum interval
    function recordSnapshot() external;

    /// @notice Get the latest snapshot
    /// @return Latest yield snapshot
    function getLatestSnapshot() external view returns (YieldSnapshot memory);

    /// @notice Get historical snapshot by index
    /// @param index Snapshot index (0 = oldest)
    /// @return Historical yield snapshot
    function getSnapshot(uint256 index) external view returns (YieldSnapshot memory);

    /// @notice Get total number of snapshots recorded
    /// @return Number of snapshots
    function getSnapshotCount() external view returns (uint256);

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    // Note: vault() returns implementation-specific type, not part of interface

    /// @notice Get minimum interval between snapshots
    /// @return Interval in seconds
    function snapshotInterval() external view returns (uint256);
}
