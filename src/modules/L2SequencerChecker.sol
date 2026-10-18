// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "../UniversalOracleBase.sol";
import { AggregatorV2V3Interface as IAggregatorV2V3 } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";
import { IL2SequencerChecker } from "./interfaces/IL2SequencerChecker.sol";

/// @title L2SequencerChecker
/// @author Robert29000
/// @notice Oracle module that blocks price reads while the L2 sequencer is down, and for a
///         configurable wait time after the sequencer status last changed.
/// @dev Overrides the `_beforeRead` hook. It calls `super._beforeRead()` first, then reads the
///      Chainlink L2 sequencer uptime feed: `answer == 0` means the sequencer is up, any other value
///      means it is down. `startedAt` is the time of the last status change.
///      Trust assumption: the sequencer uptime feed is the official Chainlink feed for this L2.
abstract contract L2SequencerChecker is UniversalOracleBase, IL2SequencerChecker {

    /// @dev Exclusive lower bound of `downtimeWait`, in seconds.
    uint256 constant MIN_DOWNTIME_WAIT = 1 seconds;
    /// @dev Exclusive upper bound of `downtimeWait`, in seconds.
    uint256 constant MAX_DOWNTIME_WAIT = 1 days;


    /// @notice The Chainlink L2 sequencer uptime feed.
    IAggregatorV2V3 public immutable sequencerAggregator;

    /// @notice Time in seconds to wait after the last sequencer status change before prices can be read.
    uint256 public downtimeWait;

    /// @notice Sets the sequencer uptime feed and the initial downtime wait.
    /// @dev Reverts with `SequencerAggregatorZeroAddress` if the feed address is zero, and with the
    ///      `_setDowntimeWait` errors if the wait is out of range. Emits `DowntimeWaitSet`.
    /// @param _sequencerAggregator Address of the Chainlink L2 sequencer uptime feed.
    /// @param _downtime_wait Initial downtime wait, in seconds.
    constructor(address _sequencerAggregator, uint256 _downtime_wait) {
        require(_sequencerAggregator != address(0), SequencerAggregatorZeroAddress());
        sequencerAggregator = IAggregatorV2V3(_sequencerAggregator);

        _setDowntimeWait(_downtime_wait);
    }


    /// @inheritdoc UniversalOracleBase
    /// @dev Calls `super._beforeRead()`, then reverts with `SequencerDown` if the uptime feed answer is not 0,
    ///      and with `GracePeriodNotOver` if `startedAt + downtimeWait > block.timestamp`.
    function _beforeRead() internal virtual override view {
        super._beforeRead();

        (, int256 answer, uint256 startedAt , , ) = sequencerAggregator.latestRoundData();

        bool isSequencerUp = answer == 0;
        require(isSequencerUp, SequencerDown());
        require(startedAt + downtimeWait <= block.timestamp, GracePeriodNotOver());
    }

    /// @inheritdoc IL2SequencerChecker
    /// @dev Only the owner can call this function. Validation and events are in `_setDowntimeWait`.
    function setDowntimeWait(uint256 _downtime_wait) external onlyOwner {
        _setDowntimeWait(_downtime_wait);
    }

    /// @notice Validates and stores a new downtime wait.
    /// @dev Both bounds are exclusive. Reverts with `DowntimeWaitBelowMinimum` if `_downtime_wait <= MIN_DOWNTIME_WAIT`,
    ///      `DowntimeWaitAboveMaximum` if `_downtime_wait >= MAX_DOWNTIME_WAIT`, and `DowntimeWaitEqualCurrent` if the
    ///      value does not change. Emits `DowntimeWaitSet`.
    /// @param _downtime_wait The new downtime wait, in seconds.
    function _setDowntimeWait(uint256 _downtime_wait) internal {
        require(_downtime_wait > MIN_DOWNTIME_WAIT, DowntimeWaitBelowMinimum());
        require(_downtime_wait < MAX_DOWNTIME_WAIT, DowntimeWaitAboveMaximum());
        require(_downtime_wait != downtimeWait, DowntimeWaitEqualCurrent());

        downtimeWait = _downtime_wait;

        emit DowntimeWaitSet(downtimeWait);
    }

}