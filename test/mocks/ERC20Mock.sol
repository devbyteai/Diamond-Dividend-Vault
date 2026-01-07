// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/// @title ERC20Mock
/// @notice A simple ERC20 token for testing purposes
/// @dev Provides unrestricted mint/burn for testing - DO NOT use in production
contract ERC20Mock is ERC20 {
    /// @notice Custom decimals for the mock token
    uint8 private immutable _decimals;

    /// @notice Initialize the mock token
    /// @param name_ Token name
    /// @param symbol_ Token symbol
    /// @param decimals_ Number of decimals (e.g., 18 for most tokens, 6 for USDC)
    constructor(string memory name_, string memory symbol_, uint8 decimals_) ERC20(name_, symbol_) {
        _decimals = decimals_;
    }

    /// @notice Returns the number of decimals
    /// @return Number of decimals for display purposes
    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    /// @notice Mint tokens to an address (unrestricted for testing)
    /// @param to Recipient address
    /// @param amount Amount to mint
    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }

    /// @notice Burn tokens from an address (unrestricted for testing)
    /// @param from Address to burn from
    /// @param amount Amount to burn
    function burn(address from, uint256 amount) external {
        _burn(from, amount);
    }
}
