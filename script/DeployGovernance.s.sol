// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Script, console2} from "forge-std/Script.sol";
import {DiamondGovernor} from "../src/governance/DiamondGovernor.sol";
import {DiamondTimelock} from "../src/governance/DiamondTimelock.sol";
import {DiamondDividendVault} from "../src/DiamondDividendVault.sol";

/// @title DeployGovernance
/// @notice Deployment script for Diamond Dividend Vault governance
/// @dev Run with: forge script script/DeployGovernance.s.sol --rpc-url $RPC_URL --broadcast
contract DeployGovernance is Script {
    // ═══════════════════════════════════════════════════════════════════════════
    // CONFIGURATION
    // ═══════════════════════════════════════════════════════════════════════════

    /// @dev Voting delay in blocks (~15 seconds per block on mainnet)
    /// 1 day = 5760 blocks
    uint48 public constant VOTING_DELAY = 5760; // ~1 day

    /// @dev Voting period in blocks
    /// 1 week = 40320 blocks
    uint32 public constant VOTING_PERIOD = 40320; // ~1 week

    /// @dev Minimum weighted shares needed to create a proposal
    uint256 public constant PROPOSAL_THRESHOLD = 10_000 ether;

    // ═══════════════════════════════════════════════════════════════════════════
    // DEPLOYMENT
    // ═══════════════════════════════════════════════════════════════════════════

    function run() external {
        // Load vault address from environment
        address vaultAddress = vm.envAddress("VAULT_ADDRESS");
        require(vaultAddress != address(0), "VAULT_ADDRESS not set");

        // Load deployer private key
        uint256 deployerKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerKey);

        console2.log("Deploying governance for vault:", vaultAddress);
        console2.log("Deployer:", deployer);

        vm.startBroadcast(deployerKey);

        // Step 1: Deploy Timelock
        // Initially, deployer is admin to setup roles
        address[] memory proposers = new address[](0);
        address[] memory executors = new address[](1);
        executors[0] = address(0); // Anyone can execute after delay

        DiamondTimelock timelock = new DiamondTimelock(proposers, executors, deployer);
        console2.log("DiamondTimelock deployed:", address(timelock));

        // Step 2: Deploy Governor
        DiamondGovernor governor = new DiamondGovernor(
            vaultAddress,
            timelock,
            VOTING_DELAY,
            VOTING_PERIOD,
            PROPOSAL_THRESHOLD
        );
        console2.log("DiamondGovernor deployed:", address(governor));

        // Step 3: Setup timelock roles
        // Grant governor the proposer and canceller roles
        timelock.grantRole(timelock.PROPOSER_ROLE(), address(governor));
        timelock.grantRole(timelock.CANCELLER_ROLE(), address(governor));
        console2.log("Governor granted PROPOSER_ROLE and CANCELLER_ROLE");

        // Step 4: Connect vault to timelock
        DiamondDividendVault vault = DiamondDividendVault(payable(vaultAddress));
        vault.setTimelock(address(timelock));
        console2.log("Vault timelock set to:", address(timelock));

        // Step 5: Optionally renounce admin role (for full decentralization)
        // WARNING: Only do this when ready - it cannot be undone!
        // timelock.renounceRole(timelock.DEFAULT_ADMIN_ROLE(), deployer);
        // console2.log("Admin role renounced - governance is now fully decentralized");

        vm.stopBroadcast();

        // Summary
        console2.log("\n=== DEPLOYMENT SUMMARY ===");
        console2.log("Vault:", vaultAddress);
        console2.log("Timelock:", address(timelock));
        console2.log("Governor:", address(governor));
        console2.log("\nConfiguration:");
        console2.log("- Voting Delay:", VOTING_DELAY, "blocks (~1 day)");
        console2.log("- Voting Period:", VOTING_PERIOD, "blocks (~1 week)");
        console2.log("- Proposal Threshold:", PROPOSAL_THRESHOLD / 1 ether, "weighted shares");
        console2.log("- Quorum: 4% of total weighted shares");
        console2.log("- Timelock Delay: 2 days");
        console2.log("\nNEXT STEPS:");
        console2.log("1. Verify contracts on Etherscan");
        console2.log("2. Consider transferring vault ownership to timelock");
        console2.log("3. Renounce timelock admin role for full decentralization");
    }
}
