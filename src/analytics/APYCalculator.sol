// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IAPYCalculator} from "./interfaces/IAPYCalculator.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";

/// @title IVaultExtended
/// @notice Extended vault interface for APY calculations
interface IVaultExtended is IERC4626 {
    function totalDividendsDistributed() external view returns (uint256);
    function getEffectiveMultiplier(address account) external view returns (uint256);
    function totalYieldHarvested() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/// @title APYCalculator
/// @notice On-chain APY calculator for Diamond Dividend Vault
/// @dev Provides real-time and historical yield analytics
contract APYCalculator is IAPYCalculator {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Basis points denominator
    uint256 private constant BPS_DENOMINATOR = 10_000;

    /// @dev Seconds in a year (365.25 days for leap year adjustment)
    uint256 private constant SECONDS_PER_YEAR = 365.25 days;

    /// @dev Maximum snapshots to retain (for gas limits)
    uint256 private constant MAX_SNAPSHOTS = 365;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The Diamond Dividend Vault contract
    IVaultExtended public immutable vault;

    /// @notice Minimum time between snapshots
    uint256 public immutable override snapshotInterval;

    /// @notice Array of historical snapshots
    YieldSnapshot[] private _snapshots;

    /// @notice Timestamp of last snapshot
    uint256 public lastSnapshotTime;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Snapshot interval not elapsed
    error SnapshotTooSoon();

    /// @dev No snapshots recorded yet
    error NoSnapshots();

    /// @dev Invalid snapshot index
    error InvalidSnapshotIndex();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize the APY calculator
    /// @param _vault Address of the Diamond Dividend Vault
    /// @param _snapshotInterval Minimum seconds between snapshots (e.g., 1 hours)
    constructor(address _vault, uint256 _snapshotInterval) {
        vault = IVaultExtended(_vault);
        snapshotInterval = _snapshotInterval;

        // Record initial snapshot
        _recordSnapshot();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CORE APY FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IAPYCalculator
    function getBlendedAPY() public view override returns (uint256) {
        APYBreakdown memory breakdown = getAPYBreakdown();
        return breakdown.blendedAPY;
    }

    /// @inheritdoc IAPYCalculator
    function getUserEffectiveAPY(address account) external view override returns (uint256) {
        uint256 baseAPY = getBlendedAPY();
        uint256 multiplier = vault.getEffectiveMultiplier(account);

        // Apply user's multiplier to base APY
        // multiplier is in BPS (10000 = 1x), so:
        // effectiveAPY = baseAPY * multiplier / BPS_DENOMINATOR
        return (baseAPY * multiplier) / BPS_DENOMINATOR;
    }

    /// @inheritdoc IAPYCalculator
    function getAPYBreakdown() public view override returns (APYBreakdown memory breakdown) {
        if (_snapshots.length < 2) {
            // Not enough data for APY calculation
            return APYBreakdown({
                vaultAPY: 0,
                dividendAPY: 0,
                blendedAPY: 0,
                calculatedAt: block.timestamp
            });
        }

        // Get comparison period (use oldest vs latest for stability)
        YieldSnapshot memory oldSnapshot = _snapshots[0];
        YieldSnapshot memory newSnapshot = _snapshots[_snapshots.length - 1];

        uint256 timeElapsed = newSnapshot.timestamp - oldSnapshot.timestamp;
        if (timeElapsed == 0) {
            return APYBreakdown({
                vaultAPY: 0,
                dividendAPY: 0,
                blendedAPY: 0,
                calculatedAt: block.timestamp
            });
        }

        // Calculate Vault APY (share price appreciation)
        uint256 vaultAPY = _calculateVaultAPY(oldSnapshot, newSnapshot, timeElapsed);

        // Calculate Dividend APY
        uint256 dividendAPY = _calculateDividendAPY(oldSnapshot, newSnapshot, timeElapsed);

        // Blended APY is sum of both (they're additive income streams)
        uint256 blendedAPY = vaultAPY + dividendAPY;

        breakdown = APYBreakdown({
            vaultAPY: vaultAPY,
            dividendAPY: dividendAPY,
            blendedAPY: blendedAPY,
            calculatedAt: block.timestamp
        });
    }

    /// @dev Calculate vault APY from asset growth
    function _calculateVaultAPY(
        YieldSnapshot memory oldSnap,
        YieldSnapshot memory newSnap,
        uint256 timeElapsed
    ) internal pure returns (uint256) {
        if (oldSnap.totalAssets == 0) return 0;

        // Asset growth ratio (scaled to avoid precision loss)
        // growth = (new - old) / old
        if (newSnap.totalAssets <= oldSnap.totalAssets) return 0;

        uint256 assetGrowth = newSnap.totalAssets - oldSnap.totalAssets;
        uint256 growthRateBps = (assetGrowth * BPS_DENOMINATOR) / oldSnap.totalAssets;

        // Annualize: APY = growthRate * (secondsPerYear / timeElapsed)
        uint256 annualizedAPY = (growthRateBps * SECONDS_PER_YEAR) / timeElapsed;

        return annualizedAPY;
    }

    /// @dev Calculate dividend APY from distribution growth
    function _calculateDividendAPY(
        YieldSnapshot memory oldSnap,
        YieldSnapshot memory newSnap,
        uint256 timeElapsed
    ) internal pure returns (uint256) {
        if (oldSnap.totalAssets == 0) return 0;

        // Dividend growth
        if (newSnap.totalDividends <= oldSnap.totalDividends) return 0;

        uint256 dividendGrowth = newSnap.totalDividends - oldSnap.totalDividends;

        // Yield rate = dividends / average assets
        uint256 avgAssets = (oldSnap.totalAssets + newSnap.totalAssets) / 2;
        if (avgAssets == 0) return 0;

        uint256 yieldRateBps = (dividendGrowth * BPS_DENOMINATOR) / avgAssets;

        // Annualize
        uint256 annualizedAPY = (yieldRateBps * SECONDS_PER_YEAR) / timeElapsed;

        return annualizedAPY;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROJECTION FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IAPYCalculator
    function estimateYield(
        uint256 depositAmount,
        uint256 holdingDays
    ) public view override returns (uint256 estimatedYield) {
        uint256 apy = getBlendedAPY();
        if (apy == 0 || depositAmount == 0 || holdingDays == 0) {
            return 0;
        }

        // yield = principal * (APY / 10000) * (days / 365.25)
        // Rearranged for precision: yield = principal * APY * days / (10000 * 365.25)
        uint256 secondsHeld = holdingDays * 1 days;

        estimatedYield = (depositAmount * apy * secondsHeld) / (BPS_DENOMINATOR * SECONDS_PER_YEAR);
    }

    /// @inheritdoc IAPYCalculator
    function estimateUserYield(
        address account,
        uint256 additionalDays
    ) external view override returns (uint256 estimatedYield) {
        uint256 userBalance = vault.balanceOf(account);
        if (userBalance == 0) return 0;

        // Get user's share value in underlying
        uint256 userAssets = vault.convertToAssets(userBalance);

        // Get user's effective APY (with multipliers)
        uint256 baseAPY = getBlendedAPY();
        uint256 multiplier = vault.getEffectiveMultiplier(account);
        uint256 effectiveAPY = (baseAPY * multiplier) / BPS_DENOMINATOR;

        if (effectiveAPY == 0 || additionalDays == 0) return 0;

        uint256 secondsHeld = additionalDays * 1 days;
        estimatedYield = (userAssets * effectiveAPY * secondsHeld) / (BPS_DENOMINATOR * SECONDS_PER_YEAR);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SNAPSHOT FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IAPYCalculator
    function recordSnapshot() external override {
        if (block.timestamp < lastSnapshotTime + snapshotInterval) {
            revert SnapshotTooSoon();
        }
        _recordSnapshot();
    }

    /// @dev Internal snapshot recording
    function _recordSnapshot() internal {
        uint256 totalAssets = vault.totalAssets();
        uint256 totalDividends = vault.totalDividendsDistributed();
        uint256 cumulativeYield = vault.totalYieldHarvested();

        YieldSnapshot memory snapshot = YieldSnapshot({
            timestamp: block.timestamp,
            totalAssets: totalAssets,
            totalDividends: totalDividends,
            cumulativeYield: cumulativeYield
        });

        // Prune old snapshots if at max
        if (_snapshots.length >= MAX_SNAPSHOTS) {
            // Remove oldest (shift array)
            for (uint256 i = 0; i < _snapshots.length - 1; i++) {
                _snapshots[i] = _snapshots[i + 1];
            }
            _snapshots.pop();
        }

        _snapshots.push(snapshot);
        lastSnapshotTime = block.timestamp;

        emit SnapshotRecorded(
            _snapshots.length - 1,
            block.timestamp,
            totalAssets,
            totalDividends
        );
    }

    /// @inheritdoc IAPYCalculator
    function getLatestSnapshot() external view override returns (YieldSnapshot memory) {
        if (_snapshots.length == 0) revert NoSnapshots();
        return _snapshots[_snapshots.length - 1];
    }

    /// @inheritdoc IAPYCalculator
    function getSnapshot(uint256 index) external view override returns (YieldSnapshot memory) {
        if (index >= _snapshots.length) revert InvalidSnapshotIndex();
        return _snapshots[index];
    }

    /// @inheritdoc IAPYCalculator
    function getSnapshotCount() external view override returns (uint256) {
        return _snapshots.length;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // HELPER VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get current real-time metrics (without recording snapshot)
    /// @return currentAssets Current vault total assets
    /// @return currentDividends Current total dividends distributed
    /// @return currentYield Current total yield harvested
    function getCurrentMetrics() external view returns (
        uint256 currentAssets,
        uint256 currentDividends,
        uint256 currentYield
    ) {
        currentAssets = vault.totalAssets();
        currentDividends = vault.totalDividendsDistributed();
        currentYield = vault.totalYieldHarvested();
    }

    /// @notice Get 7-day trailing APY (more recent data)
    /// @return APY in basis points
    function getTrailing7DayAPY() external view returns (uint256) {
        return _getTrailingAPY(7 days);
    }

    /// @notice Get 30-day trailing APY
    /// @return APY in basis points
    function getTrailing30DayAPY() external view returns (uint256) {
        return _getTrailingAPY(30 days);
    }

    /// @dev Calculate trailing APY for a given period
    function _getTrailingAPY(uint256 period) internal view returns (uint256) {
        if (_snapshots.length < 2) return 0;

        // Handle case where we don't have enough history
        if (block.timestamp < period) return 0;

        uint256 targetTime = block.timestamp - period;
        YieldSnapshot memory newSnapshot = _snapshots[_snapshots.length - 1];

        // Find oldest snapshot within period
        YieldSnapshot memory oldSnapshot = _snapshots[0];
        for (uint256 i = _snapshots.length - 1; i > 0; i--) {
            if (_snapshots[i - 1].timestamp >= targetTime) {
                oldSnapshot = _snapshots[i - 1];
            } else {
                break;
            }
        }

        uint256 timeElapsed = newSnapshot.timestamp - oldSnapshot.timestamp;
        if (timeElapsed == 0) return 0;

        uint256 vaultAPY = _calculateVaultAPY(oldSnapshot, newSnapshot, timeElapsed);
        uint256 dividendAPY = _calculateDividendAPY(oldSnapshot, newSnapshot, timeElapsed);

        return vaultAPY + dividendAPY;
    }
}
