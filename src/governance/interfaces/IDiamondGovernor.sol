// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDiamondGovernor
/// @notice Interface for Diamond Dividend Vault governance
/// @dev Extends OpenZeppelin Governor with weighted voting based on vault shares
interface IDiamondGovernor {
    // ═══════════════════════════════════════════════════════════════════════════
    // ENUMS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Types of governance proposals
    enum ProposalType {
        HoldingTierUpdate,    // Modify holding duration tier configs
        BalanceTierUpdate,    // Modify balance tier configs
        YieldReallocation,    // Change yield source allocations
        ProtocolParameter,    // General protocol parameters
        Emergency             // Emergency actions (higher quorum)
    }

    // ═══════════════════════════════════════════════════════════════════════════
    // EVENTS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Emitted when a holding tier update proposal is created
    event HoldingTierProposalCreated(
        uint256 indexed proposalId,
        uint256 tierIndex,
        uint256 minDuration,
        uint256 multiplierBps
    );

    /// @notice Emitted when a balance tier update proposal is created
    event BalanceTierProposalCreated(
        uint256 indexed proposalId,
        uint256 tierIndex,
        uint256 minBalance,
        uint256 multiplierBps
    );

    /// @notice Emitted when a yield reallocation proposal is created
    event YieldReallocationProposalCreated(
        uint256 indexed proposalId,
        address[] protocols,
        uint256[] allocations
    );

    // ═══════════════════════════════════════════════════════════════════════════
    // PROPOSAL FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    /// @notice Create a proposal to update a holding tier
    /// @param tierIndex Index of the tier to update
    /// @param minDuration New minimum duration in seconds
    /// @param multiplierBps New multiplier in basis points
    /// @param description Human-readable description
    /// @return proposalId The ID of the created proposal
    function proposeHoldingTierUpdate(
        uint256 tierIndex,
        uint256 minDuration,
        uint256 multiplierBps,
        string calldata description
    ) external returns (uint256 proposalId);

    /// @notice Create a proposal to update a balance tier
    /// @param tierIndex Index of the tier to update
    /// @param minBalance New minimum balance requirement
    /// @param multiplierBps New multiplier in basis points
    /// @param description Human-readable description
    /// @return proposalId The ID of the created proposal
    function proposeBalanceTierUpdate(
        uint256 tierIndex,
        uint256 minBalance,
        uint256 multiplierBps,
        string calldata description
    ) external returns (uint256 proposalId);

    /// @notice Create a proposal to reallocate yield sources
    /// @param protocols Array of yield source protocol addresses
    /// @param allocations Array of new allocation percentages in bps
    /// @param description Human-readable description
    /// @return proposalId The ID of the created proposal
    function proposeYieldReallocation(
        address[] calldata protocols,
        uint256[] calldata allocations,
        string calldata description
    ) external returns (uint256 proposalId);

    // ═══════════════════════════════════════════════════════════════════════════
    // VIEW FUNCTIONS
    // ═══════════════════════════════════════════════════════════════════════════

    // Note: vault() returns implementation-specific type, not part of interface

    /// @notice Get voting power for an account
    /// @dev Uses weighted shares from vault, not raw balance
    /// @param account Address to check
    /// @param blockNumber Block number for snapshot
    /// @return Voting power (weighted shares)
    function getVotes(address account, uint256 blockNumber) external view returns (uint256);

    /// @notice Check if an account can create proposals
    /// @param account Address to check
    /// @return True if account meets proposal threshold
    function canPropose(address account) external view returns (bool);
}
