// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ══════════════════════════════════════════════════════════════════════════════
//                              SAFE MATH LIBRARIES
// ══════════════════════════════════════════════════════════════════════════════

/// @title SafeMathInt
/// @notice Safe conversion and operations for signed integers
/// @dev Solidity 0.8+ has built-in overflow checks, but edge cases need explicit handling
///      Specifically: MIN_INT256 * -1 and MIN_INT256 / -1 would overflow
library SafeMathInt {
    /// @dev Minimum value for int256
    int256 private constant MIN_INT256 = type(int256).min;

    /// @dev Maximum value for int256
    int256 private constant MAX_INT256 = type(int256).max;

    /// @notice Multiplies two int256 values safely
    /// @dev Handles MIN_INT256 * -1 overflow case
    /// @param a First operand
    /// @param b Second operand
    /// @return Product of a and b
    function mul(int256 a, int256 b) internal pure returns (int256) {
        // Special case: MIN_INT256 * -1 would overflow (result is MAX_INT256 + 1)
        if (a == MIN_INT256 && b == -1) {
            revert("SafeMathInt: multiplication overflow");
        }
        return a * b;
    }

    /// @notice Divides two int256 values safely
    /// @dev Handles MIN_INT256 / -1 overflow case
    /// @param a Dividend
    /// @param b Divisor (must not be zero)
    /// @return Quotient of a / b
    function div(int256 a, int256 b) internal pure returns (int256) {
        // Special case: MIN_INT256 / -1 would overflow (result is MAX_INT256 + 1)
        if (a == MIN_INT256 && b == -1) {
            revert("SafeMathInt: division overflow");
        }
        return a / b;
    }

    /// @notice Converts uint256 to int256 safely
    /// @dev Reverts if value exceeds int256 maximum
    /// @param a The unsigned integer to convert
    /// @return The signed integer representation
    function toInt256Safe(uint256 a) internal pure returns (int256) {
        if (a > uint256(MAX_INT256)) {
            revert("SafeMathInt: value exceeds int256 max");
        }
        return int256(a);
    }
}

/// @title SafeMathUint
/// @notice Safe conversion from signed to unsigned integers
/// @dev Used for dividend calculations where result must be positive
library SafeMathUint {
    /// @notice Converts int256 to uint256 safely
    /// @dev Reverts if value is negative
    /// @param a The signed integer to convert
    /// @return The unsigned integer representation
    function toUint256Safe(int256 a) internal pure returns (uint256) {
        if (a < 0) {
            revert("SafeMathUint: value must be non-negative");
        }
        return uint256(a);
    }
}
