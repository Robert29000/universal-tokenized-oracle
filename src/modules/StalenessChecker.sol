// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "../UniversalOracleBase.sol";
import {ETTimestamp} from "../libraries/ETTimestamp.sol";
import {UnixTimestamp} from "../libraries/UnixTimestamp.sol";

import {IStalenessChecker} from "./interfaces/IStalenessChecker.sol";


contract StalenessChecker is UniversalOracleBase, IStalenessChecker {

    uint256 public immutable maxStaleness;
    uint256 public immutable tradingStaleness;
    uint256 public immutable reopenTimeWait;

    constructor(address _aggregator, uint256 _maxStaleness, uint256 _tradingStaleness, uint256 _reopenTimeWait) UniversalOracleBase(_aggregator) {
        require(_maxStaleness > 0, MaxStalenessZero());
        require(_tradingStaleness > 0, TradingStalenessZero());
        require(_maxStaleness >= _tradingStaleness, MaxStalenessLessThanTradingStaleness());
        require(_reopenTimeWait <= _tradingStaleness, ReopenTimeWaitGreaterThanTradingStaleness());


        maxStaleness = _maxStaleness;
        tradingStaleness = _tradingStaleness;
        reopenTimeWait = _reopenTimeWait;
    }

    function _checkStaleness(uint256 _updatedAt) internal override view {
        require(_updatedAt + maxStaleness >= block.timestamp, MaxStalenessReached());

        if (_updatedAt + tradingStaleness < block.timestamp) {
            (uint256 dstStartTimestamp, uint256 dstEndTimestamp) = _getDSTBoundaries(block.timestamp);

            require(ETTimestamp.isETWeekendTrading(block.timestamp, dstStartTimestamp, dstEndTimestamp, reopenTimeWait), TradingStalenessReached());
        }
    }

    function _getDSTBoundaries(uint256 _timestamp) internal pure returns (uint256, uint256) {
        (uint256 year, ,) = UnixTimestamp.getDate(_timestamp);

        return ETTimestamp.getETTransitionBoundariesInUTC(year);
    }
}