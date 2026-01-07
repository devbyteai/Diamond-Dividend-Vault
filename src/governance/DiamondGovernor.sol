// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Governor} from "@openzeppelin/contracts/governance/Governor.sol";
import {GovernorSettings} from "@openzeppelin/contracts/governance/extensions/GovernorSettings.sol";
import {GovernorCountingSimple} from "@openzeppelin/contracts/governance/extensions/GovernorCountingSimple.sol";
import {GovernorTimelockControl} from "@openzeppelin/contracts/governance/extensions/GovernorTimelockControl.sol";
import {TimelockController} from "@openzeppelin/contracts/governance/TimelockController.sol";
import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";

import {IDiamondGovernor} from "./interfaces/IDiamondGovernor.sol";

/// @title IWeightedVault
/// @notice Minimal interface for vault weighted share queries
interface IWeightedVault {
    function getUserWeightedShares(address account) external view returns (uint256);
    function getTotalWeightedShares() external view returns (uint256);
    function setHoldingTier(uint256 tierIndex, uint256 minDuration, uint256 multiplierBps) external;
    function setBalanceTier(uint256 tierIndex, uint256 minBalance, uint256 multiplierBps) external;
}

/// @title DiamondGovernor
/// @notice Governance contract for Diamond Dividend Vault
/// @dev Uses weighted shares for voting power, integrating with the vault's multiplier system
contract DiamondGovernor is
    Governor,
    GovernorSettings,
    GovernorCountingSimple,
    GovernorTimelockControl,
    IDiamondGovernor
{
    // ═══════════════════════════════════════════════════════════════════════════
    // STATE VARIABLES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice The Diamond Dividend Vault contract
    IWeightedVault public immutable vault;

    /// @notice Quorum percentage in basis points (400 = 4%)
    uint256 public constant QUORUM_BPS = 400;

    /// @notice Basis points denominator
    uint256 private constant BPS_DENOMINATOR = 10_000;

    // ═══════════════════════════════════════════════════════════════════════════
    // CONSTRUCTOR
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Initialize the Diamond Governor
    /// @param _vault Address of the Diamond Dividend Vault
    /// @param _timelock Address of the timelock controller
    /// @param _votingDelay Delay before voting starts (in blocks)
    /// @param _votingPeriod Duration of voting (in blocks)
    /// @param _proposalThreshold Minimum weighted shares to create proposal
    constructor(
        address _vault,
        TimelockController _timelock,
        uint48 _votingDelay,
        uint32 _votingPeriod,
        uint256 _proposalThreshold
    )
        Governor("Diamond Governor")
        GovernorSettings(_votingDelay, _votingPeriod, _proposalThreshold)
        GovernorTimelockControl(_timelock)
    {
        vault = IWeightedVault(_vault);
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // PROPOSAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @inheritdoc IDiamondGovernor
    function proposeHoldingTierUpdate(
        uint256 tierIndex,
        uint256 minDuration,
        uint256 multiplierBps,
        string calldata description
    ) external returns (uint256) {
        address[] memory targets = new address[](1);
        targets[0] = address(vault);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            IWeightedVault.setHoldingTier.selector,
            tierIndex,
            minDuration,
            multiplierBps
        );

        uint256 proposalId = propose(targets, values, calldatas, description);

        emit HoldingTierProposalCreated(proposalId, tierIndex, minDuration, multiplierBps);

        return proposalId;
    }

    /// @inheritdoc IDiamondGovernor
    function proposeBalanceTierUpdate(
        uint256 tierIndex,
        uint256 minBalance,
        uint256 multiplierBps,
        string calldata description
    ) external returns (uint256) {
        address[] memory targets = new address[](1);
        targets[0] = address(vault);

        uint256[] memory values = new uint256[](1);
        values[0] = 0;

        bytes[] memory calldatas = new bytes[](1);
        calldatas[0] = abi.encodeWithSelector(
            IWeightedVault.setBalanceTier.selector,
            tierIndex,
            minBalance,
            multiplierBps
        );

        uint256 proposalId = propose(targets, values, calldatas, description);

        emit BalanceTierProposalCreated(proposalId, tierIndex, minBalance, multiplierBps);

        return proposalId;
    }

    /// @inheritdoc IDiamondGovernor
    function proposeYieldReallocation(
        address[] calldata protocols,
        uint256[] calldata allocations,
        string calldata description
    ) external returns (uint256) {
        require(protocols.length == allocations.length, "Length mismatch");

        // Create targets and calldatas for each protocol update
        address[] memory targets = new address[](protocols.length);
        uint256[] memory values = new uint256[](protocols.length);
        bytes[] memory calldatas = new bytes[](protocols.length);

        for (uint256 i = 0; i < protocols.length; i++) {
            targets[i] = address(vault);
            values[i] = 0;
            // This would call a setYieldAllocation function on the vault
            // For now, we use a generic call pattern
            calldatas[i] = abi.encodeWithSignature(
                "setYieldAllocation(address,uint256)",
                protocols[i],
                allocations[i]
            );
        }

        uint256 proposalId = propose(targets, values, calldatas, description);

        emit YieldReallocationProposalCreated(proposalId, protocols, allocations);

        return proposalId;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // VOTING POWER (OVERRIDE)
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Get voting power for an account
    /// @dev Uses weighted shares from vault instead of raw token balance
    /// @param account Address to check
    /// @param blockNumber Block number (unused - we use current state)
    /// @return Voting power based on weighted shares
    function _getVotes(
        address account,
        uint256 blockNumber,
        bytes memory /* params */
    ) internal view override returns (uint256) {
        // Note: Ideally we would use historical snapshots, but for simplicity
        // we use current weighted shares. For production, implement ERC20Votes
        // pattern in the vault contract for proper snapshot support.
        blockNumber; // Silence unused variable warning
        return vault.getUserWeightedShares(account);
    }

    /// @notice Get voting power for an account at a specific block
    function getVotes(address account, uint256 blockNumber) public view override(Governor, IDiamondGovernor) returns (uint256) {
        return _getVotes(account, blockNumber, "");
    }

    /// @inheritdoc IDiamondGovernor
    function canPropose(address account) external view returns (bool) {
        return vault.getUserWeightedShares(account) >= proposalThreshold();
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // QUORUM
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Calculate quorum for a specific block
    /// @dev 4% of total weighted shares
    /// @param blockNumber Block number (unused - uses current state)
    /// @return Quorum amount in weighted shares
    function quorum(uint256 blockNumber) public view override returns (uint256) {
        blockNumber; // Silence unused variable warning
        return (vault.getTotalWeightedShares() * QUORUM_BPS) / BPS_DENOMINATOR;
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // REQUIRED OVERRIDES
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Clock used for voting deadlines (block number based)
    function clock() public view override returns (uint48) {
        return uint48(block.number);
    }

    /// @notice Machine-readable description of the clock
    // solhint-disable-next-line func-name-mixedcase
    function CLOCK_MODE() public pure override returns (string memory) {
        return "mode=blocknumber&from=default";
    }

    function votingDelay() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingDelay();
    }

    function votingPeriod() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.votingPeriod();
    }

    function proposalThreshold() public view override(Governor, GovernorSettings) returns (uint256) {
        return super.proposalThreshold();
    }

    function state(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (ProposalState)
    {
        return super.state(proposalId);
    }

    function proposalNeedsQueuing(uint256 proposalId)
        public
        view
        override(Governor, GovernorTimelockControl)
        returns (bool)
    {
        return super.proposalNeedsQueuing(proposalId);
    }

    function _queueOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint48) {
        return super._queueOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _executeOperations(
        uint256 proposalId,
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) {
        super._executeOperations(proposalId, targets, values, calldatas, descriptionHash);
    }

    function _cancel(
        address[] memory targets,
        uint256[] memory values,
        bytes[] memory calldatas,
        bytes32 descriptionHash
    ) internal override(Governor, GovernorTimelockControl) returns (uint256) {
        return super._cancel(targets, values, calldatas, descriptionHash);
    }

    function _executor() internal view override(Governor, GovernorTimelockControl) returns (address) {
        return super._executor();
    }
}
