// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "../UniversalOracleBase.sol";
import {ETTimestamp} from "../libraries/ETTimestamp.sol";
import {UnixTimestamp} from "../libraries/UnixTimestamp.sol";

import {IStalenessChecker} from "./interfaces/IStalenessChecker.sol";


contract StalenessChecker is UniversalOracleBase, IStalenessChecker {

    uint256 public immutable maxStaleness;
    uint256 public immutable tradingStaleness;

    constructor(address _aggregator, uint256 _maxStaleness, uint256 _tradingStaleness) UniversalOracleBase(_aggregator) {
        require(_maxStaleness > 0, MaxStalenessZero());
        require(_tradingStaleness > 0, TradingStalenessZero());


        maxStaleness = _maxStaleness;
        tradingStaleness = _tradingStaleness;
    }

    function _checkStaleness(uint256 _updatedAt) internal override view {
        require(_updatedAt + maxStaleness >= block.timestamp, MaxStalenessReached());

        (uint256 dstStartTimestamp, uint256 dstEndTimestamp) = _getDSTBoundaries(block.timestamp);

        if (!ETTimestamp.isETWeekendTrading(block.timestamp, dstStartTimestamp, dstEndTimestamp)) {
            require(_updatedAt + tradingStaleness >= block.timestamp, TradingStalenessReached());
        }
    }

    function _getDSTBoundaries(uint256 _timestamp) internal pure returns (uint256, uint256) {
        (uint256 year, ,) = UnixTimestamp.getDate(_timestamp);

        return ETTimestamp.getETTransitionBoundariesInUTC(year);
    }
}