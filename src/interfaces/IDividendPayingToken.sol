// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/// @title IDividendPayingToken
/// @notice Standard interface for ERC-1726 dividend-paying tokens
/// @dev Based on ERC-1726 proposal: https://eips.ethereum.org/EIPS/eip-1726
///      Enables automatic dividend distribution to token holders
interface IDividendPayingToken {
    /// @notice Emitted when dividends are distributed to token holders
    /// @param from The address distributing the dividends
    /// @param weiAmount The amount of ETH distributed
    event DividendsDistributed(address indexed from, uint256 weiAmount);

    /// @notice Emitted when a token holder withdraws their dividends
    /// @param to The address receiving the withdrawal
    /// @param weiAmount The amount of ETH withdrawn
    event DividendWithdrawn(address indexed to, uint256 weiAmount);

    /// @notice Distributes ETH to token holders as dividends
    /// @dev MUST emit the `DividendsDistributed` event if ETH is distributed
    ///      MUST revert if no tokens exist (division by zero)
    ///      MAY be called by anyone; uses msg.value as dividend amount
    function distributeDividends() external payable;

    /// @notice Withdraws the accumulated dividend of the caller
    /// @dev MUST emit the `DividendWithdrawn` event if dividend is withdrawn
    ///      MUST update withdrawn tracking to prevent double-withdrawal
    function withdrawDividend() external;

    /// @notice View the withdrawable dividend for an address
    /// @param owner The address of a token holder
    /// @return The amount of dividend in wei that `owner` can withdraw
    function dividendOf(address owner) external view returns (uint256);
}

/// @title IDividendPayingTokenOptional
/// @notice Optional interface for detailed dividend tracking
/// @dev Provides breakdown of accumulated vs withdrawn dividends
interface IDividendPayingTokenOptional {
    /// @notice View the withdrawable dividend for an address
    /// @dev Alias for dividendOf(), included for interface completeness
    /// @param owner The address of a token holder
    /// @return The amount of dividend in wei that `owner` can withdraw
    function withdrawableDividendOf(address owner) external view returns (uint256);

    /// @notice View the amount of dividend already withdrawn
    /// @param owner The address of a token holder
    /// @return The amount of dividend in wei that `owner` has withdrawn
    function withdrawnDividendOf(address owner) external view returns (uint256);

    /// @notice View the total accumulated dividend (withdrawn + withdrawable)
    /// @dev accumulativeDividendOf = withdrawableDividendOf + withdrawnDividendOf
    /// @param owner The address of a token holder
    /// @return The total amount of dividend in wei that `owner` has earned
    function accumulativeDividendOf(address owner) external view returns (uint256);
}
