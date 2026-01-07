// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDiamondDividendVault
/// @notice Interface for DiamondDividendVault - first-ever ERC-4626 + ERC-1726 hybrid yield vault
/// @dev Implements multi-dimensional weighted dividend distribution based on holding duration and balance tiers
interface IDiamondDividendVault {
    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Configuration for holding duration reward tiers
    /// @dev Users earn higher multipliers the longer they hold tokens
    struct HoldingTier {
        /// @notice Minimum holding duration in seconds to qualify for this tier
        uint256 minDuration;
        /// @notice Multiplier in basis points (10000 = 1x, 15000 = 1.5x, 20000 = 2x)
        uint256 multiplierBps;
    }

    /// @notice Configuration for balance-based reward tiers
    /// @dev Used for anti-whale mechanics (larger holders get reduced multipliers)
    struct BalanceTier {
        /// @notice Minimum token balance to qualify for this tier
        uint256 minBalance;
        /// @notice Multiplier in basis points (10000 = 1x, 9000 = 0.9x for anti-whale)
        uint256 multiplierBps;
    }

    /// @notice Tracks a user's holding history for duration-based rewards
    struct HoldingInfo {
        /// @notice Timestamp when user first received tokens (resets if balance goes to 0)
        uint256 firstHoldTimestamp;
        /// @notice Timestamp when holding was last reset (when balance went to 0)
        uint256 lastResetTimestamp;
        /// @notice Cumulative holding time across all holding periods
        uint256 totalHoldingTime;
    }

    /// @notice Configuration for external yield source integrations
    struct YieldSource {
        /// @notice Address of the yield protocol (Aave, Compound, etc.)
        address protocol;
        /// @notice Allocation percentage in basis points (10000 = 100%)
        uint256 allocationBps;
        /// @notice Whether this source is currently active
        bool active;
        /// @notice Function selector for deposit calls
        bytes4 depositSelector;
        /// @notice Function selector for withdraw calls
        bytes4 withdrawSelector;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a holding tier configuration is updated
    /// @param tierIndex Index of the tier that was updated
    /// @param minDuration New minimum duration requirement
    /// @param multiplierBps New multiplier in basis points
    event HoldingTierUpdated(uint256 indexed tierIndex, uint256 minDuration, uint256 multiplierBps);

    /// @notice Emitted when a balance tier configuration is updated
    /// @param tierIndex Index of the tier that was updated
    /// @param minBalance New minimum balance requirement
    /// @param multiplierBps New multiplier in basis points
    event BalanceTierUpdated(uint256 indexed tierIndex, uint256 minBalance, uint256 multiplierBps);

    /// @notice Emitted when a new yield source is added
    /// @param protocol Address of the yield protocol
    /// @param allocationBps Initial allocation percentage
    event YieldSourceAdded(address indexed protocol, uint256 allocationBps);

    /// @notice Emitted when a yield source is removed
    /// @param protocol Address of the removed yield protocol
    event YieldSourceRemoved(address indexed protocol);

    /// @notice Emitted when yield is harvested from an external source
    /// @param source Address of the yield source
    /// @param amount Amount of yield harvested
    event YieldHarvested(address indexed source, uint256 amount);

    /// @notice Emitted when a dividend is sent cross-chain
    /// @param dstChainId Destination LayerZero chain ID
    /// @param recipient Address of the dividend recipient
    /// @param amount Amount of dividend sent
    event CrossChainDividendSent(uint16 indexed dstChainId, address indexed recipient, uint256 amount);

    /// @notice Emitted when a dividend is received from another chain
    /// @param srcChainId Source LayerZero chain ID
    /// @param recipient Address of the dividend recipient
    /// @param amount Amount of dividend received
    event CrossChainDividendReceived(uint16 indexed srcChainId, address indexed recipient, uint256 amount);

    /// @notice Emitted when the governance timelock address is updated
    /// @param oldTimelock Previous timelock address
    /// @param newTimelock New timelock address
    event TimelockUpdated(address indexed oldTimelock, address indexed newTimelock);

    // ═══════════════════════════════════════════════════════════════════════════
    // GOVERNANCE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get the governance timelock address
    /// @return The timelock controller address
    function timelock() external view returns (address);

    /// @notice Set the governance timelock address
    /// @dev Only callable by owner
    /// @param _timelock New timelock controller address
    function setTimelock(address _timelock) external;

    /// @notice Get a user's weighted shares (used for governance voting)
    /// @param account Address to query
    /// @return Weighted share amount
    function getUserWeightedShares(address account) external view returns (uint256);

    /// @notice Get total weighted shares across all users
    /// @return Total weighted shares
    function getTotalWeightedShares() external view returns (uint256);

    // ═══════════════════════════════════════════════════════════════════════════
    // HOLDING DURATION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get the complete holding information for an account
    /// @param account Address to query
    /// @return info Holding information struct
    function getHoldingInfo(address account) external view returns (HoldingInfo memory info);

    /// @notice Get the holding duration multiplier for an account
    /// @param account Address to query
    /// @return Multiplier in basis points (10000 = 1x)
    function getHoldingMultiplier(address account) external view returns (uint256);

    /// @notice Get the current holding duration for an account
    /// @param account Address to query
    /// @return Duration in seconds
    function getHoldingDuration(address account) external view returns (uint256);

    // ═══════════════════════════════════════════════════════════════════════════
    // TIERED REWARDS FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get the balance tier for an account
    /// @param account Address to query
    /// @return tierIndex Index of the balance tier
    /// @return multiplierBps Multiplier for that tier in basis points
    function getBalanceTier(address account) external view returns (uint256 tierIndex, uint256 multiplierBps);

    /// @notice Get the effective (combined) multiplier for an account
    /// @dev Combines holding duration and balance tier multipliers
    /// @param account Address to query
    /// @return Combined multiplier in basis points
    function getEffectiveMultiplier(address account) external view returns (uint256);

    // ═══════════════════════════════════════════════════════════════════════════
    // CROSS-CHAIN FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Claim dividend and send to another chain via LayerZero
    /// @dev Requires msg.value to cover LayerZero fees
    /// @param dstChainId Destination LayerZero chain ID
    function claimCrossChainDividend(uint16 dstChainId) external payable;

    /// @notice Estimate the LayerZero fee for cross-chain dividend claim
    /// @param dstChainId Destination LayerZero chain ID
    /// @param recipient Address of the dividend recipient
    /// @param amount Amount of dividend to send
    /// @return Estimated fee in native token (ETH)
    function estimateCrossChainFee(
        uint16 dstChainId,
        address recipient,
        uint256 amount
    ) external view returns (uint256);

    // ═══════════════════════════════════════════════════════════════════════════
    // YIELD SOURCE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Harvest yield from all configured yield sources
    function harvestYield() external;

    /// @notice Rebalance allocations across yield sources
    function rebalanceYieldSources() external;

    /// @notice Get total yield generated across all sources
    /// @return Total yield in underlying asset terms
    function getTotalYieldGenerated() external view returns (uint256);
}
