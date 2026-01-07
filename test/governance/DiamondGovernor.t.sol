// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test, console2} from "forge-std/Test.sol";
import {DiamondGovernor} from "../../src/governance/DiamondGovernor.sol";
import {DiamondTimelock} from "../../src/governance/DiamondTimelock.sol";
import {DiamondDividendVault} from "../../src/DiamondDividendVault.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IGovernor} from "@openzeppelin/contracts/governance/IGovernor.sol";
import {ERC20Mock} from "../mocks/ERC20Mock.sol";

/// @title DiamondGovernorTest
/// @notice Comprehensive tests for Diamond Dividend Vault governance
contract DiamondGovernorTest is Test {
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE
    // ═══════════════════════════════════════════════════════════════════════════

    DiamondGovernor public governor;
    DiamondTimelock public timelock;
    DiamondDividendVault public vault;
    ERC20Mock public asset;

    address public deployer = address(1);
    address public voter1 = address(2);
    address public voter2 = address(3);
    address public voter3 = address(4);
    address public nonVoter = address(5);

    uint48 constant VOTING_DELAY = 1; // 1 block
    uint32 constant VOTING_PERIOD = 50400; // ~1 week in blocks
    uint256 constant PROPOSAL_THRESHOLD = 1000 ether;

    // ═══════════════════════════════════════════════════════════════════════════
    // SETUP
    // ═══════════════════════════════════════════════════════════════════════════

    function setUp() public {
        vm.startPrank(deployer);

        // Deploy underlying asset
        asset = new ERC20Mock("Test Asset", "TEST", 18);

        // Deploy vault
        vault = new DiamondDividendVault(asset, "Diamond Vault", "DVT", address(0));

        // Setup timelock with governor as proposer/executor
        address[] memory proposers = new address[](1);
        address[] memory executors = new address[](1);
        proposers[0] = address(0); // Will set to governor after deployment
        executors[0] = address(0); // Anyone can execute after delay

        timelock = new DiamondTimelock(proposers, executors, deployer);

        // Deploy governor
        governor = new DiamondGovernor(
            address(vault),
            timelock,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD
        );

        // Grant governor roles on timelock
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));

        // Connect vault to timelock
        vault.setTimelock(address(timelock));

        // Grant timelock the right to call vault functions
        // Note: In production, vault ownership should transfer to timelock

        vm.stopPrank();

        // Setup voters with deposits
        _setupVoters();
    }

    function _setupVoters() internal {
        // Mint assets to voters
        asset.mint(voter1, 10_000 ether);
        asset.mint(voter2, 5_000 ether);
        asset.mint(voter3, 2_000 ether);
        asset.mint(nonVoter, 100 ether);

        // Voters deposit into vault
        vm.startPrank(voter1);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(10_000 ether, voter1);
        vm.stopPrank();

        vm.startPrank(voter2);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(5_000 ether, voter2);
        vm.stopPrank();

        vm.startPrank(voter3);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(2_000 ether, voter3);
        vm.stopPrank();

        vm.startPrank(nonVoter);
        asset.approve(address(vault), type(uint256).max);
        vault.deposit(100 ether, nonVoter);
        vm.stopPrank();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // INITIALIZATION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_Initialization() public view {
        assertEq(address(governor.vault()), address(vault));
        assertEq(governor.votingDelay(), VOTING_DELAY);
        assertEq(governor.votingPeriod(), VOTING_PERIOD);
        assertEq(governor.proposalThreshold(), PROPOSAL_THRESHOLD);
        assertEq(governor.QUORUM_BPS(), 400); // 4%
    }

    function test_VaultTimelockSet() public view {
        assertEq(vault.timelock(), address(timelock));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VOTING POWER TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_VotingPowerEqualsWeightedShares() public view {
        uint256 voter1Shares = vault.getUserWeightedShares(voter1);
        uint256 voter1Votes = governor.getVotes(voter1, block.number);
        assertEq(voter1Votes, voter1Shares);
    }

    function test_VotingPowerIncreasesWithTime() public {
        uint256 initialVotes = governor.getVotes(voter1, block.number);

        // Fast forward 30 days to hit next tier
        vm.warp(block.timestamp + 30 days);

        uint256 newVotes = governor.getVotes(voter1, block.number);
        assertGt(newVotes, initialVotes);
    }

    function test_CanPropose() public view {
        // voter1 has 10k shares, threshold is 1k
        assertTrue(governor.canPropose(voter1));

        // nonVoter has only 100 shares
        assertFalse(governor.canPropose(nonVoter));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // QUORUM TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_QuorumCalculation() public view {
        uint256 totalWeighted = vault.getTotalWeightedShares();
        uint256 expectedQuorum = (totalWeighted * 400) / 10_000; // 4%
        assertEq(governor.quorum(block.number), expectedQuorum);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROPOSAL TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ProposeHoldingTierUpdate() public {
        vm.prank(voter1);
        uint256 proposalId = governor.proposeHoldingTierUpdate(
            0, // tierIndex
            15 days, // new minDuration
            11_000, // 1.1x multiplier
            "Increase base tier duration"
        );

        assertGt(proposalId, 0);
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Pending));
    }

    function test_ProposeBalanceTierUpdate() public {
        vm.prank(voter1);
        uint256 proposalId = governor.proposeBalanceTierUpdate(
            1, // tierIndex
            2_000 ether, // new minBalance
            10_500, // 1.05x multiplier
            "Adjust mid-tier balance requirement"
        );

        assertGt(proposalId, 0);
    }

    function test_ProposeYieldReallocation() public {
        address[] memory protocols = new address[](2);
        protocols[0] = address(100);
        protocols[1] = address(101);

        uint256[] memory allocations = new uint256[](2);
        allocations[0] = 6000; // 60%
        allocations[1] = 4000; // 40%

        vm.prank(voter1);
        uint256 proposalId = governor.proposeYieldReallocation(
            protocols,
            allocations,
            "Rebalance yield sources"
        );

        assertGt(proposalId, 0);
    }

    function test_RevertProposalBelowThreshold() public {
        vm.prank(nonVoter);
        vm.expectRevert(); // GovernorInsufficientProposerVotes
        governor.proposeHoldingTierUpdate(0, 15 days, 11_000, "Should fail");
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VOTING TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_VoteOnProposal() public {
        // Create proposal
        vm.prank(voter1);
        uint256 proposalId = governor.proposeHoldingTierUpdate(
            0,
            15 days,
            11_000,
            "Test proposal"
        );

        // Advance past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote
        vm.prank(voter1);
        governor.castVote(proposalId, 1); // 1 = For

        vm.prank(voter2);
        governor.castVote(proposalId, 1); // 1 = For

        // Check votes
        (uint256 against, uint256 forVotes, uint256 abstain) = governor.proposalVotes(proposalId);
        assertGt(forVotes, 0);
        assertEq(against, 0);
        assertEq(abstain, 0);
    }

    function test_ProposalSucceedsWithQuorum() public {
        // Create proposal
        vm.prank(voter1);
        uint256 proposalId = governor.proposeHoldingTierUpdate(
            0,
            15 days,
            11_000,
            "Test proposal"
        );

        // Advance past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote with majority
        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        vm.prank(voter3);
        governor.castVote(proposalId, 1);

        // Advance past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Check succeeded
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Succeeded));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EXECUTION TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_ExecuteProposalThroughTimelock() public {
        // Transfer vault ownership to timelock for this test
        vm.prank(deployer);
        vault.transferOwnership(address(timelock));

        // Create proposal
        vm.prank(voter1);
        uint256 proposalId = governor.proposeHoldingTierUpdate(
            0,
            15 days,
            11_000,
            "Update tier 0"
        );

        // Advance past voting delay
        vm.roll(block.number + VOTING_DELAY + 1);

        // Vote with majority
        vm.prank(voter1);
        governor.castVote(proposalId, 1);

        vm.prank(voter2);
        governor.castVote(proposalId, 1);

        vm.prank(voter3);
        governor.castVote(proposalId, 1);

        // Advance past voting period
        vm.roll(block.number + VOTING_PERIOD + 1);

        // Queue
        address[] memory targets = new address[](1);
        targets[0] = address(vault);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSignature(
            "setHoldingTier(uint256,uint256,uint256)",
            0,
            15 days,
            11_000
        );

        bytes32 descriptionHash = keccak256(bytes("Update tier 0"));

        governor.queue(targets, values, calldatas, descriptionHash);

        // Advance past timelock delay
        vm.warp(block.timestamp + 2 days + 1);

        // Execute
        governor.execute(targets, values, calldatas, descriptionHash);

        // Verify state changed
        assertEq(uint256(governor.state(proposalId)), uint256(IGovernor.ProposalState.Executed));
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EDGE CASE TESTS
    // ═══════════════════════════════════════════════════════════════════════════

    function test_YieldReallocationLengthMismatch() public {
        address[] memory protocols = new address[](2);
        protocols[0] = address(100);
        protocols[1] = address(101);

        uint256[] memory allocations = new uint256[](1);
        allocations[0] = 10_000;

        vm.prank(voter1);
        vm.expectRevert("Length mismatch");
        governor.proposeYieldReallocation(protocols, allocations, "Should fail");
    }

    function test_VotingPowerWithZeroBalance() public view {
        address nobody = address(999);
        uint256 votes = governor.getVotes(nobody, block.number);
        assertEq(votes, 0);
    }
}
