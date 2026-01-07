// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {ILoyaltyBadge} from "./interfaces/ILoyaltyBadge.sol";
import {BadgeSVGRenderer} from "./BadgeSVGRenderer.sol";

/// @title IVaultHolding
/// @notice Minimal interface for vault holding queries
interface IVaultHolding {
    function getHoldingDuration(address account) external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
}

/// @title LoyaltyBadge
/// @notice Soulbound NFT badges for Diamond Dividend Vault holders
/// @dev Non-transferable achievement NFTs based on holding duration
contract LoyaltyBadge is ERC721, Ownable, ILoyaltyBadge {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTANTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Holding duration requirements for each tier
    uint256 public constant BRONZE_DURATION = 30 days;
    uint256 public constant SILVER_DURATION = 90 days;
    uint256 public constant GOLD_DURATION = 180 days;
    uint256 public constant DIAMOND_DURATION = 365 days;

    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The Diamond Dividend Vault contract
    IVaultHolding public immutable vault;

    /// @notice Next token ID to mint
    uint256 private _nextTokenId;

    /// @notice Mapping from holder address to their badge token ID
    mapping(address holder => uint256 tokenId) private _holderBadge;

    /// @notice Mapping from holder address to badge info
    mapping(address holder => BadgeInfo info) private _badgeInfo;

    /// @notice Count of badges at each tier
    mapping(BadgeTier tier => uint256 count) private _tierCounts;

    // ═══════════════════════════════════════════════════════════════════════════
    // ERRORS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev User already has a badge
    error AlreadyHasBadge();

    /// @dev User is not eligible for any badge tier
    error NotEligible();

    /// @dev User is not eligible for upgrade
    error NotEligibleForUpgrade();

    /// @dev Soulbound tokens cannot be transferred
    error Soulbound();

    /// @dev User does not have a badge to upgrade
    error NoBadgeToUpgrade();

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize the loyalty badge contract
    /// @param _vault Address of the Diamond Dividend Vault
    constructor(address _vault) ERC721("Diamond Loyalty Badge", "LOYALTY") Ownable(msg.sender) {
        vault = IVaultHolding(_vault);
        _nextTokenId = 1; // Start from 1
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // CORE FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILoyaltyBadge
    function mint() external override {
        if (_holderBadge[msg.sender] != 0) revert AlreadyHasBadge();

        (bool eligible, BadgeTier tier) = checkEligibility(msg.sender);
        if (!eligible) revert NotEligible();

        uint256 tokenId = _nextTokenId++;
        uint256 holdingDuration = vault.getHoldingDuration(msg.sender);
        uint256 balance = vault.balanceOf(msg.sender);

        _badgeInfo[msg.sender] = BadgeInfo({
            tier: tier,
            earnedAt: block.timestamp,
            holdingDuration: holdingDuration,
            balanceAtMint: balance
        });

        _holderBadge[msg.sender] = tokenId;
        _tierCounts[tier]++;

        _safeMint(msg.sender, tokenId);

        emit BadgeMinted(msg.sender, tokenId, tier, holdingDuration);
    }

    /// @inheritdoc ILoyaltyBadge
    function upgradeBadge() external override {
        uint256 tokenId = _holderBadge[msg.sender];
        if (tokenId == 0) revert NoBadgeToUpgrade();

        BadgeInfo storage info = _badgeInfo[msg.sender];
        BadgeTier currentTier = info.tier;

        (bool eligible, BadgeTier newTier) = checkEligibility(msg.sender);
        if (!eligible || newTier <= currentTier) revert NotEligibleForUpgrade();

        // Update tier counts
        _tierCounts[currentTier]--;
        _tierCounts[newTier]++;

        // Update badge info
        uint256 holdingDuration = vault.getHoldingDuration(msg.sender);
        info.tier = newTier;
        info.holdingDuration = holdingDuration;

        emit BadgeUpgraded(msg.sender, tokenId, currentTier, newTier);
    }

    /// @inheritdoc ILoyaltyBadge
    function checkEligibility(address account) public view override returns (bool eligible, BadgeTier tier) {
        uint256 duration = vault.getHoldingDuration(account);
        uint256 balance = vault.balanceOf(account);

        // Must have tokens to earn badge
        if (balance == 0) return (false, BadgeTier.None);

        // Determine tier based on holding duration
        if (duration >= DIAMOND_DURATION) {
            return (true, BadgeTier.Diamond);
        } else if (duration >= GOLD_DURATION) {
            return (true, BadgeTier.Gold);
        } else if (duration >= SILVER_DURATION) {
            return (true, BadgeTier.Silver);
        } else if (duration >= BRONZE_DURATION) {
            return (true, BadgeTier.Bronze);
        }

        return (false, BadgeTier.None);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc ILoyaltyBadge
    function getBadgeInfo(address account) external view override returns (BadgeInfo memory) {
        return _badgeInfo[account];
    }

    /// @inheritdoc ILoyaltyBadge
    function getTierName(BadgeTier tier) external pure override returns (string memory) {
        if (tier == BadgeTier.Bronze) return "Bronze";
        if (tier == BadgeTier.Silver) return "Silver";
        if (tier == BadgeTier.Gold) return "Gold";
        if (tier == BadgeTier.Diamond) return "Diamond";
        return "None";
    }

    /// @inheritdoc ILoyaltyBadge
    function getTierDuration(BadgeTier tier) external pure override returns (uint256) {
        if (tier == BadgeTier.Bronze) return BRONZE_DURATION;
        if (tier == BadgeTier.Silver) return SILVER_DURATION;
        if (tier == BadgeTier.Gold) return GOLD_DURATION;
        if (tier == BadgeTier.Diamond) return DIAMOND_DURATION;
        return 0;
    }

    /// @inheritdoc ILoyaltyBadge
    function totalBadges() external view override returns (uint256) {
        return _nextTokenId - 1;
    }

    /// @inheritdoc ILoyaltyBadge
    function getTierCounts() external view override returns (
        uint256 bronze,
        uint256 silver,
        uint256 gold,
        uint256 diamond
    ) {
        return (
            _tierCounts[BadgeTier.Bronze],
            _tierCounts[BadgeTier.Silver],
            _tierCounts[BadgeTier.Gold],
            _tierCounts[BadgeTier.Diamond]
        );
    }

    /// @notice Get token ID for a holder
    /// @param holder Address to query
    /// @return Token ID (0 if no badge)
    function getTokenId(address holder) external view returns (uint256) {
        return _holderBadge[holder];
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ERC721 OVERRIDES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Generate on-chain token URI with SVG
    function tokenURI(uint256 tokenId) public view override returns (string memory) {
        address holder = ownerOf(tokenId);
        BadgeInfo memory info = _badgeInfo[holder];

        return BadgeSVGRenderer.renderTokenURI(info, tokenId, holder);
    }

    /// @dev Block all transfers - tokens are soulbound
    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override returns (address) {
        address from = _ownerOf(tokenId);

        // Allow minting (from == address(0))
        // Block all transfers and burns
        if (from != address(0)) {
            revert Soulbound();
        }

        return super._update(to, tokenId, auth);
    }

    /// @dev Override approve to prevent approvals (soulbound)
    function approve(address, uint256) public pure override {
        revert Soulbound();
    }

    /// @dev Override setApprovalForAll to prevent approvals (soulbound)
    function setApprovalForAll(address, bool) public pure override {
        revert Soulbound();
    }
}
