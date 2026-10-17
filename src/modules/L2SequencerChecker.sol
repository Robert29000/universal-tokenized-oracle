// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "../UniversalOracleBase.sol";
import { AggregatorV2V3Interface as IAggregatorV2V3 } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";
import { IL2SequencerChecker } from "./interfaces/IL2SequencerChecker.sol";

abstract contract L2SequencerChecker is UniversalOracleBase, IL2SequencerChecker {

    uint256 constant MIN_DOWNTIME_WAIT = 1 seconds;
    uint256 constant MAX_DOWNTIME_WAIT = 1 days;


    IAggregatorV2V3 public immutable sequencerAggregator;

    uint256 public downtimeWait;

    constructor(address _sequencerAggregator, uint256 _downtime_wait) {
        require(_sequencerAggregator != address(0), SequencerAggregatorZeroAddress());
        sequencerAggregator = IAggregatorV2V3(_sequencerAggregator);

        _setDowntimeWait(_downtime_wait);
    }


    function _chainUptimeCheck() internal virtual override view {
        (, int256 answer, uint256 startedAt , , ) = sequencerAggregator.latestRoundData();

        bool isSequncerUp = answer == 0;
        require(isSequncerUp, SequencerDown());
        require(startedAt + downtimeWait <= block.timestamp, GracePeriodNotOver());
    }

    function setDowntimeWait(uint256 _downtime_wait) external onlyOwner {
        _setDowntimeWait(_downtime_wait);
    }

    function _setDowntimeWait(uint256 _downtime_wait) internal {
        require(_downtime_wait > MIN_DOWNTIME_WAIT, DowntimeWaitBelowMinimum());
        require(_downtime_wait < MAX_DOWNTIME_WAIT, DowntimeWaitAboveMaximum());
        require(_downtime_wait != downtimeWait, DowntimeWaitEqualCurrent());

        downtimeWait = _downtime_wait;

        emit DowntimeWaitSet(downtimeWait);
    }

}