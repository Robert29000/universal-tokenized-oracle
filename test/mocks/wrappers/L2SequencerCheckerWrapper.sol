// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UniversalOracleBase} from "src/UniversalOracleBase.sol";
import {L2SequencerChecker} from "src/modules/L2SequencerChecker.sol";

/// @notice Concrete oracle composed of UniversalOracleBase + L2SequencerChecker only.
contract L2SequencerCheckerWrapper is L2SequencerChecker {
    constructor(address _aggregator, address _sequencerAggregator, uint256 _downtimeWait)
        UniversalOracleBase(_aggregator)
        L2SequencerChecker(_sequencerAggregator, _downtimeWait)
    {}

    function exposed_price() external view returns (uint256) {
        return _price();
    }

    function exposed_beforeRead() external view {
        _beforeRead();
    }

    function exposed_setDowntimeWait(uint256 _downtimeWait) external {
        _setDowntimeWait(_downtimeWait);
    }

    function exposed_MIN_DOWNTIME_WAIT() external pure returns (uint256) {
        return MIN_DOWNTIME_WAIT;
    }

    function exposed_MAX_DOWNTIME_WAIT() external pure returns (uint256) {
        return MAX_DOWNTIME_WAIT;
    }
}
