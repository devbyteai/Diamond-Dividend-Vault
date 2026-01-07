// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {APYCalculator, IAPYCalculator} from "../../src/analytics/APYCalculator.sol";
import {DiamondDividendVault} from "../../src/DiamondDividendVault.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/// @title APYCalculatorTest
/// @notice Tests for APY calculation and yield projections
contract APYCalculatorTest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    APYCalculator public calculator;
    DiamondDividendVault public vault;
    ERC20Mock public asset;

    address public deployer = address(1);
    address public user1 = address(2);
    address public user2 = address(3);

    uint256 constant SNAPSHOT_INTERVAL = 1 hours;

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy underlying asset
        asset = new ERC20Mock("Test Asset", "TEST", 18);

        // Deploy vault
        vault = new DiamondDividendVault(asset, "Diamond Vault", "DVT", address(0));

        vm.stopPrank();

        // Setup users with deposits BEFORE deploying calculator
        _setupUsers();

        // Deploy APY calculator after deposits so initial snapshot has assets
        vm.prank(deployer);
        calculator = new APYCalculator(address(vault), SNAPSHOT_INTERVAL);
    }

    function _setupUsers() internal {
        // Mint and deposit for users
        asset.mint(user1, 100_000 ether);
        asset.mint(user2, 50_000 ether);

        vm.startPrank(user1);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(100_000 ether, user1);
        vm.stopPrank();

        vm.startPrank(user2);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(50_000 ether, user2);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Initialization() public view {
        assertEq(address(calculator.vault()), address(vault));
        assertEq(calculator.snapshotInterval(), SNAPSHOT_INTERVAL);
        assertEq(calculator.getSnapshotCount(), 1); // Initial snapshot
    }

    function test_InitialSnapshot() public view {
        IAPYCalculator.YieldSnapshot memory snapshot = calculator.getLatestSnapshot();
        assertGt(snapshot.totalAssets, 0);
        assertEq(snapshot.timestamp, block.timestamp);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // SNAPSHOT TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_RecordSnapshot() public {
        // Fast forward past interval
        vm.warp(block.timestamp + SNAPSHOT_INTERVAL + 1);

        calculator.recordSnapshot();
        assertEq(calculator.getSnapshotCount(), 2);
    }

    function test_RevertSnapshotTooSoon() public {
        // Try to record immediately
        vm.expectRevert(APYCalculator.SnapshotTooSoon.selector);
        calculator.recordSnapshot();
    }

    function test_SnapshotPruning() public {
        // Record many snapshots
        for (uint256 i = 0; i < 400; i++) {
            vm.warp(block.timestamp + SNAPSHOT_INTERVAL + 1);
            calculator.recordSnapshot();
        }

        // Should be capped at MAX_SNAPSHOTS
        assertLe(calculator.getSnapshotCount(), 365);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // APY CALCULATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_InitialAPYIsZero() public view {
        // With only one snapshot, APY should be 0
        assertEq(calculator.getBlendedAPY(), 0);
    }

    function test_APYAfterYieldGrowth() public {
        // Record initial state
        vm.warp(block.timestamp + 1 days);
        calculator.recordSnapshot();

        // Simulate yield by adding assets to vault (mimics yield harvest)
        asset.mint(address(vault), 10_000 ether); // 10k yield on 150k = 6.67%

        // Record new snapshot
        vm.warp(block.timestamp + 1 days);
        calculator.recordSnapshot();

        // APY should be non-zero now
        uint256 apy = calculator.getBlendedAPY();
        assertGt(apy, 0);
        console2.log("Calculated APY (bps):", apy);
    }

    function test_APYBreakdown() public {
        // Setup yield scenario
        vm.warp(block.timestamp + 1 days);
        calculator.recordSnapshot();

        // Add yield
        asset.mint(address(vault), 5_000 ether);

        vm.warp(block.timestamp + 7 days);
        calculator.recordSnapshot();

        IAPYCalculator.APYBreakdown memory breakdown = calculator.getAPYBreakdown();
        assertEq(breakdown.calculatedAt, block.timestamp);
        assertGt(breakdown.vaultAPY, 0);
    }

    function test_UserEffectiveAPY() public {
        // Setup base APY
        vm.warp(block.timestamp + 1 days);
        calculator.recordSnapshot();

        asset.mint(address(vault), 10_000 ether);

        vm.warp(block.timestamp + 7 days);
        calculator.recordSnapshot();

        uint256 baseAPY = calculator.getBlendedAPY();
        uint256 user1APY = calculator.getUserEffectiveAPY(user1);

        // User1 has default multiplier, should be close to base
        // May differ based on holding/balance tiers
        console2.log("Base APY:", baseAPY);
        console2.log("User1 APY:", user1APY);
    }

    function test_UserAPYIncreasesWithTime() public {
        // Setup base APY
        vm.warp(block.timestamp + 1 days);
        calculator.recordSnapshot();

        asset.mint(address(vault), 10_000 ether);

        vm.warp(block.timestamp + 7 days);
        calculator.recordSnapshot();

        uint256 initialAPY = calculator.getUserEffectiveAPY(user1);

        // Fast forward to higher tier
        vm.warp(block.timestamp + 30 days);

        uint256 laterAPY = calculator.getUserEffectiveAPY(user1);

        // APY should increase due to higher holding multiplier
        assertGe(laterAPY, initialAPY);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROJECTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_EstimateYield() public {
        // Setup base APY (10% annualized)
        vm.warp(block.timestamp + 1 days);
        calculator.recordSnapshot();

        // Add 1% yield over 1 day = ~365% APY
        asset.mint(address(vault), 1_500 ether); // 1% of 150k

        vm.warp(block.timestamp + 1 days);
        calculator.recordSnapshot();

        uint256 estimate = calculator.estimateYield(10_000 ether, 365);
        assertGt(estimate, 0);
        console2.log("Estimated 1-year yield on 10k:", estimate / 1 ether, "tokens");
    }

    function test_EstimateYieldZeroDeposit() public view {
        uint256 estimate = calculator.estimateYield(0, 365);
        assertEq(estimate, 0);
    }

    function test_EstimateYieldZeroDays() public view {
        uint256 estimate = calculator.estimateYield(10_000 ether, 0);
        assertEq(estimate, 0);
    }

    function test_EstimateUserYield() public {
        // Setup APY
        vm.warp(block.timestamp + 1 days);
        calculator.recordSnapshot();

        asset.mint(address(vault), 1_500 ether);

        vm.warp(block.timestamp + 1 days);
        calculator.recordSnapshot();

        uint256 estimate = calculator.estimateUserYield(user1, 30);
        assertGt(estimate, 0);
        console2.log("User1 estimated 30-day yield:", estimate / 1 ether, "tokens");
    }

    function test_EstimateUserYieldNoBalance() public view {
        address nobody = address(999);
        uint256 estimate = calculator.estimateUserYield(nobody, 30);
        assertEq(estimate, 0);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // TRAILING APY TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Trailing7DayAPY() public {
        // Record multiple snapshots over time
        for (uint256 i = 0; i < 10; i++) {
            vm.warp(block.timestamp + 1 days);
            if (i == 5) {
                // Add yield in the middle
                asset.mint(address(vault), 1_000 ether);
            }
            calculator.recordSnapshot();
        }

        uint256 trailing7d = calculator.getTrailing7DayAPY();
        uint256 trailing30d = calculator.getTrailing30DayAPY();

        console2.log("7-day trailing APY:", trailing7d);
        console2.log("30-day trailing APY:", trailing30d);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // METRIC TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_GetCurrentMetrics() public {
        (uint256 assets, uint256 dividends, uint256 yield) = calculator.getCurrentMetrics();

        assertGt(assets, 0);
        // Dividends and yield may be 0 initially
        console2.log("Current assets:", assets / 1 ether);
        console2.log("Current dividends:", dividends / 1 ether);
        console2.log("Current yield:", yield / 1 ether);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_APYWithNoAssets() public {
        // Deploy fresh calculator with empty vault
        vm.startPrank(deployer);
        DiamondDividendVault emptyVault = new DiamondDividendVault(
            asset,
            "Empty Vault",
            "EMPTY",
            address(0)
        );
        APYCalculator emptyCalc = new APYCalculator(address(emptyVault), SNAPSHOT_INTERVAL);
        vm.stopPrank();

        // Should not revert, just return 0
        uint256 apy = emptyCalc.getBlendedAPY();
        assertEq(apy, 0);
    }

    function test_GetSnapshotInvalidIndex() public {
        vm.expectRevert(APYCalculator.InvalidSnapshotIndex.selector);
        calculator.getSnapshot(999);
    }
}
