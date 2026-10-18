// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "./UniversalOracleBase.sol";
import { L2SequencerChecker } from "./modules/L2SequencerChecker.sol";
import { StalenessChecker } from "./modules/StalenessChecker.sol";
import { CorporatePauseChecker } from "./modules/CorporatePauseChecker.sol";

/// @title BasicUniversalOracle
/// @author Robert29000
/// @notice Tokenized-stock oracle that combines three checks on each price read:
///         L2 sequencer uptime, corporate pause and staleness (with US market weekend hours).
///         It has no external price getter: a derived contract must expose `_price()` to read prices.
/// @dev C3 linearization (most derived first): BasicUniversalOracle, CorporatePauseChecker,
///      StalenessChecker, L2SequencerChecker, UniversalOracleBase. Because each module calls
///      `super` first, the checks run in this order:
///      - `_beforeRead`: L2 sequencer check (`L2SequencerChecker`), then corporate pause check
///        (`CorporatePauseChecker`).
///      - `_afterRead`: price > 0 (`UniversalOracleBase`), then staleness (`StalenessChecker`).
///      This contract does not add an external price getter. The validated price is available
///      only through the internal `_price()` function.
contract BasicUniversalOracle is L2SequencerChecker, StalenessChecker, CorporatePauseChecker {
    /// @notice Deploys the oracle and configures all modules. The deployer becomes the owner.
    /// @dev Each module validates its own parameters and reverts with its own errors.
    /// @param _aggregator Address of the Chainlink-compatible price feed of the tokenized stock.
    /// @param _sequencerAggregator Address of the Chainlink L2 sequencer uptime feed.
    /// @param _downtimeWait Wait time in seconds after the sequencer comes back up. Must be more than `MIN_DOWNTIME_WAIT` and less than `MAX_DOWNTIME_WAIT`.
    /// @param _maxStaleness Maximum age of the price in seconds at any time. Must be more than 0 and at least `_tradingStaleness`.
    /// @param _tradingStaleness Maximum age of the price in seconds while the market trades. Must be more than 0.
    /// @param _reopenTimeWait Grace period in seconds after the Sunday 20:00 ET reopen. Must be at most `_tradingStaleness`.
    /// @param _pauseConfigurator Address of the `IPauseConfigurator` of the corporate provider. Must not be the zero address.
    constructor(
        address _aggregator,
        address _sequencerAggregator,
        uint256 _downtimeWait,
        uint256 _maxStaleness,
        uint256 _tradingStaleness,
        uint256 _reopenTimeWait,
        address _pauseConfigurator
    )
        UniversalOracleBase(_aggregator)
        L2SequencerChecker(_sequencerAggregator, _downtimeWait)
        StalenessChecker(_maxStaleness, _tradingStaleness, _reopenTimeWait)
        CorporatePauseChecker(_pauseConfigurator)
    {}

    /// @inheritdoc UniversalOracleBase
    /// @dev Runs the L2 sequencer check, then the corporate pause check.
    function _beforeRead() internal view override(UniversalOracleBase, L2SequencerChecker, CorporatePauseChecker) {
        super._beforeRead();
    }

    /// @inheritdoc UniversalOracleBase
    /// @dev Runs the price > 0 check, then the staleness checks.
    function _afterRead(RoundData memory _round) internal view override(UniversalOracleBase, StalenessChecker) {
        super._afterRead(_round);
    }
}
