// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

/// @title  IOracleRegistry
/// @notice Interface Chainlink queries to obtain per-token oracle parameters for
///         tokenized-equity price feeds.
/// @author Coinbase
interface IOracleRegistry {
    // ============================================================
    //                          EVENTS
    // ============================================================

    /// @notice Emitted when the oracle pause state for `token` changes.
    /// @param token  The token whose pause flag was updated.
    /// @param paused The new pause state.
    event OraclePausedSet(address indexed token, bool paused);

    // ============================================================
    //                          ERRORS
    // ============================================================

    /// @notice The zero address was supplied where a non-zero address is required.
    error ZeroAddress();

    // ============================================================
    //                        QUERY INTERFACE
    // ============================================================

    /// @notice Returns the oracle parameters Chainlink uses to validate and gate
    ///         price feed publication for `token`.
    ///
    /// @dev    `multiplier` is read live from the token's own `multiplier()` view
    ///         and returned as-is; `paused` reflects the operator-set pause flag.
    ///
    /// @param token   The B20 token address.
    /// @return multiplier The token's current WAD-precision multiplier (uint256).
    /// @return paused     True if the oracle feed for this token should be paused.
    function getOracleParams(address token) external view returns (uint256 multiplier, bool paused);

    // ============================================================
    //                      ADMIN INTERFACE
    // ============================================================

    /// @notice Sets the oracle pause flag for `token`. Emits {OraclePausedSet}.
    ///
    /// @param token  The B20 token address.
    /// @param paused True to signal Chainlink to pause the feed; false to unpause.
    function setOraclePaused(address token, bool paused) external;
}