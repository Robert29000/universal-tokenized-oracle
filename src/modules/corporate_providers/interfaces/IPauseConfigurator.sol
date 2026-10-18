// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


/// @title IPauseConfigurator
/// @author Robert29000
/// @notice Adapter that tells the oracle if the corporate provider of a tokenized stock has paused its price.
/// @dev Implemented by one configurator per provider (Robinhood, Coinbase, xStocks) and read by
///      `CorporatePauseChecker` before each price read. Each provider defines a pause differently, for
///      example during a corporate action (split, dividend) that changes the token multiplier.
interface IPauseConfigurator {
    /// @notice Returns true if the price of the tokenized stock must not be used now.
    /// @return True if the corporate provider reports a pause.
    function isPaused() external view returns (bool);
}