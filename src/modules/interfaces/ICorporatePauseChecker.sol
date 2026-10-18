// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title ICorporatePauseChecker
/// @author Robert29000
/// @notice Errors and events of the corporate pause module.
interface ICorporatePauseChecker {
    /// @notice The pause configurator address is the zero address.
    error PauseConfiguratorZeroAddress();
    /// @notice The new pause configurator address is the same as the current one.
    error PauseConfiguratorEqualCurrent();
    /// @notice The price read is blocked because the corporate provider reports a pause.
    error CorporatePaused();


    /// @notice Emitted when the pause configurator is set.
    /// @param pauseConfigurator Address of the new pause configurator.
    event PauseConfiguratorSet(address pauseConfigurator);
}