// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


import { IPauseConfigurator } from "./interfaces/IPauseConfigurator.sol";
import { IOraclePausable } from "./interfaces/IRobinhoodOraclePausable.sol";

/// @title RobinhoodPauseConfigurator
/// @author Robert29000
/// @notice Pause configurator for Robinhood tokenized stocks. It forwards the oracle pause flag of the Robinhood contract.
/// @dev `isPaused()` returns `oraclePausable.oraclePaused()` without changes.
///      Trust assumption: the Robinhood contract and the account that sets its pause flag are trusted.
contract RobinhoodPauseConfigurator is IPauseConfigurator {

    /// @notice The Robinhood oracle-pausable address given to the constructor is the zero address.
    error OraclePausableZeroAddress();

    /// @dev The Robinhood contract that exposes the oracle pause flag.
    IOraclePausable immutable oraclePausable;

    /// @notice Sets the Robinhood contract to read.
    /// @dev Reverts with `OraclePausableZeroAddress` if `_oraclePausable` is the zero address.
    /// @param _oraclePausable Address of the Robinhood contract that implements `IOraclePausable`.
    constructor(address _oraclePausable) {
        require(_oraclePausable != address(0), OraclePausableZeroAddress());
        oraclePausable = IOraclePausable(_oraclePausable);
    }

    /// @inheritdoc IPauseConfigurator
    /// @dev Returns `oraclePausable.oraclePaused()`.
    function isPaused() external view returns (bool) {
        return oraclePausable.oraclePaused();
    }

}