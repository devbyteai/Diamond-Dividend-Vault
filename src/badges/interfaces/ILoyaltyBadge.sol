// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title ILoyaltyBadge
/// @notice Interface for Diamond Dividend Vault loyalty badges
/// @dev Soulbound (non-transferable) NFTs awarded for holding duration milestones
interface ILoyaltyBadge {
    // ═══════════════════════════════════════════════════════════════════════════
    // ENUMS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Badge tier levels
    enum BadgeTier {
        None,       // No badge
        Bronze,     // 30 days
        Silver,     // 90 days
        Gold,       // 180 days
        Diamond     // 365 days
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // STRUCTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Badge metadata
    struct BadgeInfo {
        /// @notice Badge tier
        BadgeTier tier;
        /// @notice Timestamp when badge was earned
        uint256 earnedAt;
        /// @notice Holding duration when earned (seconds)
        uint256 holdingDuration;
        /// @notice Token balance when earned
        uint256 balanceAtMint;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a new badge is minted
    event BadgeMinted(
        address indexed recipient,
        uint256 indexed tokenId,
        BadgeTier tier,
        uint256 holdingDuration
    );

    /// @notice Emitted when a badge is upgraded to a higher tier
    event BadgeUpgraded(
        address indexed holder,
        uint256 indexed tokenId,
        BadgeTier oldTier,
        BadgeTier newTier
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Mint a badge if user is eligible
    /// @dev Checks holding duration from vault, reverts if not eligible
    function mint() external;

    /// @notice Upgrade existing badge to higher tier if eligible
    /// @dev Only upgrades if user qualifies for higher tier than current
    function upgradeBadge() external;

    /// @notice Check if an address is eligible for a badge (or upgrade)
    /// @param account Address to check
    /// @return eligible True if can mint or upgrade
    /// @return tier The tier they qualify for
    function checkEligibility(address account) external view returns (bool eligible, BadgeTier tier);

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get badge info for a holder
    /// @param account Address to query
    /// @return Badge information struct
    function getBadgeInfo(address account) external view returns (BadgeInfo memory);

    /// @notice Get the tier name as a string
    /// @param tier Tier enum value
    /// @return Tier name string
    function getTierName(BadgeTier tier) external pure returns (string memory);

    /// @notice Get minimum holding duration for a tier
    /// @param tier Tier to query
    /// @return Duration in seconds
    function getTierDuration(BadgeTier tier) external pure returns (uint256);

    // Note: vault() returns implementation-specific type, not part of interface

    /// @notice Get total badges minted
    /// @return Count of badges
    function totalBadges() external view returns (uint256);

    /// @notice Get count of badges at each tier
    /// @return bronze Bronze tier count
    /// @return silver Silver tier count
    /// @return gold Gold tier count
    /// @return diamond Diamond tier count
    function getTierCounts() external view returns (
        uint256 bronze,
        uint256 silver,
        uint256 gold,
        uint256 diamond
    );
}
