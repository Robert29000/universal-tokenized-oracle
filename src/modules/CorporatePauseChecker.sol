// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "../UniversalOracleBase.sol";

import { ICorporatePauseChecker } from "./interfaces/ICorporatePauseChecker.sol";
import { IPauseConfigurator } from "./corporate_providers/interfaces/IPauseConfigurator.sol";

/// @title CorporatePauseChecker
/// @author Robert29000
/// @notice Oracle module that blocks price reads while the corporate provider of the tokenized
///         stock (for example Robinhood, Coinbase or xStocks) reports a pause.
/// @dev Overrides the `_beforeRead` hook: it calls `super._beforeRead()` first, then reverts with
///      `CorporatePaused` if `pauseConfigurator.isPaused()` returns true. A revert in the
///      configurator also blocks the read.
///      Trust assumption: the pause configurator and the provider contract that it reads are trusted.
///      The owner can replace the configurator at any time.
abstract contract CorporatePauseChecker is UniversalOracleBase, ICorporatePauseChecker {

    /// @notice The adapter that reports the pause state of the corporate provider.
    IPauseConfigurator public pauseConfigurator;
    
    /// @notice Sets the initial pause configurator.
    /// @dev Reverts with `PauseConfiguratorZeroAddress` if `_pauseConfigurator` is the zero address. Emits `PauseConfiguratorSet`.
    /// @param _pauseConfigurator Address of the `IPauseConfigurator` implementation.
    constructor(address _pauseConfigurator) {
        _setPauseConfigurator(_pauseConfigurator);
    }

    /// @inheritdoc UniversalOracleBase
    /// @dev Calls `super._beforeRead()`, then reverts with `CorporatePaused` if the pause configurator reports a pause.
    function _beforeRead() internal virtual override view {
        super._beforeRead();

        bool isPaused = pauseConfigurator.isPaused();
        require(!isPaused, CorporatePaused());
    }

    /// @notice Replaces the pause configurator.
    /// @dev Only the owner can call this function. Reverts with `PauseConfiguratorZeroAddress` or
    ///      `PauseConfiguratorEqualCurrent`. Emits `PauseConfiguratorSet`.
    /// @param _pauseConfigurator Address of the new `IPauseConfigurator` implementation.
    function setPauseConfigurator(address _pauseConfigurator) external onlyOwner {
        _setPauseConfigurator(_pauseConfigurator);
    }

    /// @notice Validates and stores a new pause configurator.
    /// @dev Reverts with `PauseConfiguratorZeroAddress` if the address is zero and with
    ///      `PauseConfiguratorEqualCurrent` if it is the current configurator. Emits `PauseConfiguratorSet`.
    /// @param _pauseConfigurator Address of the new `IPauseConfigurator` implementation.
    function _setPauseConfigurator(address _pauseConfigurator) internal {
        require(_pauseConfigurator != address(0), PauseConfiguratorZeroAddress());
        require(_pauseConfigurator != address(pauseConfigurator), PauseConfiguratorEqualCurrent());

        pauseConfigurator = IPauseConfigurator(_pauseConfigurator);

        emit PauseConfiguratorSet(_pauseConfigurator);
    }

}