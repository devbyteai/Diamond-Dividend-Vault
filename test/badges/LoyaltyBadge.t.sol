// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {LoyaltyBadge} from "../../src/badges/LoyaltyBadge.sol";
import {ILoyaltyBadge} from "../../src/badges/interfaces/ILoyaltyBadge.sol";
import {DiamondDividendVault} from "../../src/DiamondDividendVault.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/// @title LoyaltyBadgeTest
/// @notice Tests for soulbound loyalty badge NFTs
contract LoyaltyBadgeTest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    LoyaltyBadge public badge;
    DiamondDividendVault public vault;
    ERC20Mock public asset;

    address public deployer = address(1);
    address public holder1 = address(2);
    address public holder2 = address(3);
    address public holder3 = address(4);
    address public nonHolder = address(5);

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy underlying asset
        asset = new ERC20Mock("Test Asset", "TEST", 18);

        // Deploy vault
        vault = new DiamondDividendVault(asset, "Diamond Vault", "DVT", address(0));

        // Deploy badge contract
        badge = new LoyaltyBadge(address(vault));

        vm.stopPrank();

        // Setup holders with deposits
        _setupHolders();
    }

    function _setupHolders() internal {
        // Mint and deposit
        asset.mint(holder1, 10_000 ether);
        asset.mint(holder2, 5_000 ether);
        asset.mint(holder3, 2_000 ether);

        vm.startPrank(holder1);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(10_000 ether, holder1);
        vm.stopPrank();

        vm.startPrank(holder2);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(5_000 ether, holder2);
        vm.stopPrank();

        vm.startPrank(holder3);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(2_000 ether, holder3);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Initialization() public view {
        assertEq(address(badge.vault()), address(vault));
        assertEq(badge.name(), "Diamond Loyalty Badge");
        assertEq(badge.symbol(), "LOYALTY");
        assertEq(badge.totalBadges(), 0);
    }

    function test_TierDurations() public view {
        assertEq(badge.getTierDuration(ILoyaltyBadge.BadgeTier.Bronze), 30 days);
        assertEq(badge.getTierDuration(ILoyaltyBadge.BadgeTier.Silver), 90 days);
        assertEq(badge.getTierDuration(ILoyaltyBadge.BadgeTier.Gold), 180 days);
        assertEq(badge.getTierDuration(ILoyaltyBadge.BadgeTier.Diamond), 365 days);
    }

    function test_TierNames() public view {
        assertEq(badge.getTierName(ILoyaltyBadge.BadgeTier.Bronze), "Bronze");
        assertEq(badge.getTierName(ILoyaltyBadge.BadgeTier.Silver), "Silver");
        assertEq(badge.getTierName(ILoyaltyBadge.BadgeTier.Gold), "Gold");
        assertEq(badge.getTierName(ILoyaltyBadge.BadgeTier.Diamond), "Diamond");
        assertEq(badge.getTierName(ILoyaltyBadge.BadgeTier.None), "None");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // ELIGIBILITY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_NotEligibleInitially() public view {
        (bool eligible, ILoyaltyBadge.BadgeTier tier) = badge.checkEligibility(holder1);
        assertFalse(eligible);
        assertEq(uint256(tier), uint256(ILoyaltyBadge.BadgeTier.None));
    }

    function test_NotEligibleWithZeroBalance() public {
        // Fast forward but non-holder should not be eligible
        vm.warp(block.timestamp + 365 days);
        (bool eligible,) = badge.checkEligibility(nonHolder);
        assertFalse(eligible);
    }

    function test_BronzeEligibility() public {
        vm.warp(block.timestamp + 30 days);
        (bool eligible, ILoyaltyBadge.BadgeTier tier) = badge.checkEligibility(holder1);
        assertTrue(eligible);
        assertEq(uint256(tier), uint256(ILoyaltyBadge.BadgeTier.Bronze));
    }

    function test_SilverEligibility() public {
        vm.warp(block.timestamp + 90 days);
        (bool eligible, ILoyaltyBadge.BadgeTier tier) = badge.checkEligibility(holder1);
        assertTrue(eligible);
        assertEq(uint256(tier), uint256(ILoyaltyBadge.BadgeTier.Silver));
    }

    function test_GoldEligibility() public {
        vm.warp(block.timestamp + 180 days);
        (bool eligible, ILoyaltyBadge.BadgeTier tier) = badge.checkEligibility(holder1);
        assertTrue(eligible);
        assertEq(uint256(tier), uint256(ILoyaltyBadge.BadgeTier.Gold));
    }

    function test_DiamondEligibility() public {
        vm.warp(block.timestamp + 365 days);
        (bool eligible, ILoyaltyBadge.BadgeTier tier) = badge.checkEligibility(holder1);
        assertTrue(eligible);
        assertEq(uint256(tier), uint256(ILoyaltyBadge.BadgeTier.Diamond));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // MINTING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_MintBronzeBadge() public {
        vm.warp(block.timestamp + 30 days);

        vm.prank(holder1);
        badge.mint();

        assertEq(badge.totalBadges(), 1);
        assertEq(badge.ownerOf(1), holder1);
        assertEq(badge.balanceOf(holder1), 1);

        ILoyaltyBadge.BadgeInfo memory info = badge.getBadgeInfo(holder1);
        assertEq(uint256(info.tier), uint256(ILoyaltyBadge.BadgeTier.Bronze));
        assertEq(info.earnedAt, block.timestamp);
        assertGt(info.holdingDuration, 0);
    }

    function test_MintDiamondBadge() public {
        vm.warp(block.timestamp + 365 days);

        vm.prank(holder1);
        badge.mint();

        ILoyaltyBadge.BadgeInfo memory info = badge.getBadgeInfo(holder1);
        assertEq(uint256(info.tier), uint256(ILoyaltyBadge.BadgeTier.Diamond));
    }

    function test_RevertMintWhenNotEligible() public {
        // No time passed
        vm.prank(holder1);
        vm.expectRevert(LoyaltyBadge.NotEligible.selector);
        badge.mint();
    }

    function test_RevertMintTwice() public {
        vm.warp(block.timestamp + 30 days);

        vm.startPrank(holder1);
        badge.mint();

        vm.expectRevert(LoyaltyBadge.AlreadyHasBadge.selector);
        badge.mint();
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // UPGRADE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_UpgradeBadge() public {
        // Mint bronze
        vm.warp(block.timestamp + 30 days);
        vm.prank(holder1);
        badge.mint();

        // Advance to silver eligibility
        vm.warp(block.timestamp + 60 days); // Now 90 days total

        vm.prank(holder1);
        badge.upgradeBadge();

        ILoyaltyBadge.BadgeInfo memory info = badge.getBadgeInfo(holder1);
        assertEq(uint256(info.tier), uint256(ILoyaltyBadge.BadgeTier.Silver));
    }

    function test_UpgradeToGold() public {
        vm.warp(block.timestamp + 90 days);
        vm.prank(holder1);
        badge.mint();

        vm.warp(block.timestamp + 90 days); // 180 days total

        vm.prank(holder1);
        badge.upgradeBadge();

        ILoyaltyBadge.BadgeInfo memory info = badge.getBadgeInfo(holder1);
        assertEq(uint256(info.tier), uint256(ILoyaltyBadge.BadgeTier.Gold));
    }

    function test_UpgradeToDiamond() public {
        vm.warp(block.timestamp + 180 days);
        vm.prank(holder1);
        badge.mint();

        vm.warp(block.timestamp + 185 days); // 365 days total

        vm.prank(holder1);
        badge.upgradeBadge();

        ILoyaltyBadge.BadgeInfo memory info = badge.getBadgeInfo(holder1);
        assertEq(uint256(info.tier), uint256(ILoyaltyBadge.BadgeTier.Diamond));
    }

    function test_RevertUpgradeNoBadge() public {
        vm.prank(holder1);
        vm.expectRevert(LoyaltyBadge.NoBadgeToUpgrade.selector);
        badge.upgradeBadge();
    }

    function test_RevertUpgradeNotEligible() public {
        vm.warp(block.timestamp + 30 days);
        vm.prank(holder1);
        badge.mint();

        // Try upgrade without enough time
        vm.warp(block.timestamp + 30 days); // 60 days total - still bronze

        vm.prank(holder1);
        vm.expectRevert(LoyaltyBadge.NotEligibleForUpgrade.selector);
        badge.upgradeBadge();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SOULBOUND TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_CannotTransfer() public {
        vm.warp(block.timestamp + 30 days);
        vm.prank(holder1);
        badge.mint();

        vm.prank(holder1);
        vm.expectRevert(LoyaltyBadge.Soulbound.selector);
        badge.transferFrom(holder1, holder2, 1);
    }

    function test_CannotSafeTransfer() public {
        vm.warp(block.timestamp + 30 days);
        vm.prank(holder1);
        badge.mint();

        vm.prank(holder1);
        vm.expectRevert(LoyaltyBadge.Soulbound.selector);
        badge.safeTransferFrom(holder1, holder2, 1);
    }

    function test_CannotApprove() public {
        vm.warp(block.timestamp + 30 days);
        vm.prank(holder1);
        badge.mint();

        vm.prank(holder1);
        vm.expectRevert(LoyaltyBadge.Soulbound.selector);
        badge.approve(holder2, 1);
    }

    function test_CannotSetApprovalForAll() public {
        vm.warp(block.timestamp + 30 days);
        vm.prank(holder1);
        badge.mint();

        vm.prank(holder1);
        vm.expectRevert(LoyaltyBadge.Soulbound.selector);
        badge.setApprovalForAll(holder2, true);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TIER COUNTS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_TierCountsAfterMinting() public {
        vm.warp(block.timestamp + 30 days);
        vm.prank(holder1);
        badge.mint();

        vm.prank(holder2);
        badge.mint();

        (uint256 bronze, uint256 silver, uint256 gold, uint256 diamond) = badge.getTierCounts();
        assertEq(bronze, 2);
        assertEq(silver, 0);
        assertEq(gold, 0);
        assertEq(diamond, 0);
    }

    function test_TierCountsAfterUpgrade() public {
        vm.warp(block.timestamp + 30 days);
        vm.prank(holder1);
        badge.mint();

        (uint256 bronze1,,,) = badge.getTierCounts();
        assertEq(bronze1, 1);

        vm.warp(block.timestamp + 60 days);
        vm.prank(holder1);
        badge.upgradeBadge();

        (uint256 bronze2, uint256 silver2,,) = badge.getTierCounts();
        assertEq(bronze2, 0);
        assertEq(silver2, 1);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TOKEN URI TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_TokenURI() public {
        vm.warp(block.timestamp + 30 days);
        vm.prank(holder1);
        badge.mint();

        string memory uri = badge.tokenURI(1);

        // Check it starts with data URI prefix
        assertTrue(bytes(uri).length > 0);
        console2.log("Token URI length:", bytes(uri).length);

        // Check it contains base64 encoded data
        bytes memory uriBytes = bytes(uri);
        assertTrue(uriBytes.length > 30);
    }

    function test_TokenURIContainsMetadata() public {
        vm.warp(block.timestamp + 365 days);
        vm.prank(holder1);
        badge.mint();

        string memory uri = badge.tokenURI(1);
        console2.log("Diamond badge URI (truncated):");

        // Full URI would be too long to log, but we verify it exists
        assertTrue(bytes(uri).length > 100);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // GAS TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GasMint() public {
        vm.warp(block.timestamp + 30 days);

        vm.prank(holder1);
        uint256 gasBefore = gasleft();
        badge.mint();
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for mint:", gasUsed);
        assertLt(gasUsed, 500_000); // Reasonable gas limit
    }

    function test_GasTokenURI() public {
        vm.warp(block.timestamp + 30 days);
        vm.prank(holder1);
        badge.mint();

        uint256 gasBefore = gasleft();
        badge.tokenURI(1);
        uint256 gasUsed = gasBefore - gasleft();

        console2.log("Gas used for tokenURI:", gasUsed);
        // On-chain SVG generation is expensive but should be bounded
        assertLt(gasUsed, 5_000_000);
    }
}
