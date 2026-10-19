// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ETTimestamp} from "src/libraries/ETTimestamp.sol";

/// @notice Exposes every internal ETTimestamp library function as an external call.
/// @dev Also deployed by the Python differential harness (test/differential/python/), so keep the ABI stable.
contract ETTimestampWrapper {
    function getETTransitionBoundariesInUTC(uint256 _year) external pure returns (uint256, uint256) {
        return ETTimestamp.getETTransitionBoundariesInUTC(_year);
    }

    function isETWeekend(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd) external pure returns (bool) {
        return ETTimestamp.isETWeekend(_timestamp, _dstStart, _dstEnd);
    }

    function isETWeekendTrading(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd) external pure returns (bool) {
        return ETTimestamp.isETWeekendTrading(_timestamp, _dstStart, _dstEnd);
    }

    function isETWeekendTradingWithGrace(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd, uint256 _grace)
        external
        pure
        returns (bool)
    {
        return ETTimestamp.isETWeekendTrading(_timestamp, _dstStart, _dstEnd, _grace);
    }

    function checkETWeekendTrading(uint256 _etTimestamp, uint256 _grace) external pure returns (bool) {
        return ETTimestamp._checkETWeekendTrading(_etTimestamp, _grace);
    }

    function getLastETFridayCloseInUTC(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd)
        external
        pure
        returns (uint256)
    {
        return ETTimestamp.getLastETFridayCloseInUTC(_timestamp, _dstStart, _dstEnd);
    }

    function getETOffset(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd) external pure returns (uint256) {
        return ETTimestamp.getETOffset(_timestamp, _dstStart, _dstEnd);
    }

    function toETTimestamp(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd) external pure returns (uint256) {
        return ETTimestamp.toETTimestamp(_timestamp, _dstStart, _dstEnd);
    }

    function adjustedUTCForETOffset(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd)
        external
        pure
        returns (uint256)
    {
        return ETTimestamp._adjustedUTCForETOffset(_timestamp, _dstStart, _dstEnd);
    }
}
