// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title IL2SequencerChecker
/// @author Robert29000
/// @notice Errors, events and external functions of the L2 sequencer module.
interface IL2SequencerChecker {
    /// @notice The sequencer uptime feed address is the zero address.
    error SequencerAggregatorZeroAddress();
    /// @notice The downtime wait is less than or equal to the minimum.
    error DowntimeWaitBelowMinimum();
    /// @notice The downtime wait is greater than or equal to the maximum.
    error DowntimeWaitAboveMaximum();
    /// @notice The new downtime wait is the same as the current one.
    error DowntimeWaitEqualCurrent();
    /// @notice The price read is blocked because the sequencer uptime feed reports that the sequencer is down.
    error SequencerDown();
    /// @notice The price read is blocked because the downtime wait after the last sequencer status change is not over.
    error GracePeriodNotOver();

    /// @notice Emitted when the downtime wait is set (in the constructor or by the owner).
    /// @param downtimeWait The new downtime wait, in seconds.
    event DowntimeWaitSet(uint256 downtimeWait);

    /// @notice Changes the time to wait after the last sequencer status change before prices can be read.
    /// @param _downtime_wait The new downtime wait, in seconds.
    function setDowntimeWait(uint256 _downtime_wait) external;
}