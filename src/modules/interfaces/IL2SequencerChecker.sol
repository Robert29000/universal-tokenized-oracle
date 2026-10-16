// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IL2SequencerChecker {
    error SequencerAggregatorZeroAddress();
    error DowntimeWaitBelowMinimum();
    error DowntimeWaitAboveMaximum();
    error DowntimeWaitEqualCurrent();
    error SequencerDown();
    error GracePeriodNotOver();

    event DowntimeWaitSet(uint256 downtimeWait);

    function setDowntimeWait(uint256 _downtime_wait) external;
}