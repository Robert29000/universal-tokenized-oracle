// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "../UniversalOracleBase.sol";
import {ETTimestamp} from "../libraries/ETTimestamp.sol";
import {UnixTimestamp} from "../libraries/UnixTimestamp.sol";

import {IStalenessChecker} from "./interfaces/IStalenessChecker.sol";


abstract contract StalenessChecker is UniversalOracleBase, IStalenessChecker {

    uint256 public immutable maxStaleness;
    uint256 public immutable tradingStaleness;
    uint256 public immutable reopenTimeWait;

    constructor(uint256 _maxStaleness, uint256 _tradingStaleness, uint256 _reopenTimeWait) {
        require(_maxStaleness > 0, MaxStalenessZero());
        require(_tradingStaleness > 0, TradingStalenessZero());
        require(_maxStaleness >= _tradingStaleness, MaxStalenessLessThanTradingStaleness());
        require(_reopenTimeWait <= _tradingStaleness, ReopenTimeWaitGreaterThanTradingStaleness());


        maxStaleness = _maxStaleness;
        tradingStaleness = _tradingStaleness;
        reopenTimeWait = _reopenTimeWait;
    }

    function _afterRead(RoundData memory _round) internal virtual override view {
        super._afterRead(_round);

        require(_round.updatedAt + maxStaleness >= block.timestamp, MaxStalenessReached());

        if (_round.updatedAt + tradingStaleness < block.timestamp) {
            (uint256 dstStartTimestamp, uint256 dstEndTimestamp) = _getDSTBoundaries(block.timestamp);

            if (!ETTimestamp.isETWeekendTrading(block.timestamp, dstStartTimestamp, dstEndTimestamp, reopenTimeWait)) {
                revert TradingStalenessReached();
            } else {
                uint256 lastFridayCloseInUTC = ETTimestamp.getLastETFridayCloseInUTC(block.timestamp, dstStartTimestamp, dstEndTimestamp);
                require(_round.updatedAt + tradingStaleness >= lastFridayCloseInUTC, TradingStalenessReached());
            }
        }
    }

    function _getDSTBoundaries(uint256 _timestamp) internal pure returns (uint256, uint256) {
        (uint256 year, ,) = UnixTimestamp.getDate(_timestamp);

        return ETTimestamp.getETTransitionBoundariesInUTC(year);
    }
}