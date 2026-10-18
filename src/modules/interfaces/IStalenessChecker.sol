// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title IStalenessChecker
/// @author Robert29000
/// @notice Errors and configuration getters of the staleness module.
interface IStalenessChecker {

    /// @notice The max staleness given to the constructor is zero.
    error MaxStalenessZero();
    /// @notice The trading staleness given to the constructor is zero.
    error TradingStalenessZero();
    /// @notice The price is older than `maxStaleness`.
    error MaxStalenessReached();
    /// @notice The price is older than `tradingStaleness` while the market trades, or, during the weekend
    ///         closure or the reopen grace period, it was older than `tradingStaleness` at the last
    ///         Friday 20:00 ET close.
    error TradingStalenessReached();
    /// @notice The max staleness given to the constructor is less than the trading staleness.
    error MaxStalenessLessThanTradingStaleness();
    /// @notice The reopen time wait given to the constructor is greater than the trading staleness.
    error ReopenTimeWaitGreaterThanTradingStaleness();

    /// @notice Returns the maximum age of the price at any time.
    /// @return The maximum age of the price, in seconds.
    function maxStaleness() external view returns (uint256);
    /// @notice Returns the maximum age of the price while the market trades.
    /// @return The maximum age of the price while the market trades, in seconds.
    function tradingStaleness() external view returns (uint256);
    /// @notice Returns the grace period after the Sunday 20:00 ET reopen during which the weekend rules still apply.
    /// @return The grace period after the weekly reopen, in seconds.
    function reopenTimeWait() external view returns (uint256);

}