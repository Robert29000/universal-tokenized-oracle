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

    function isETWeekendByDate(uint256 _etYear, uint256 _etMonth, uint256 _etDay) external pure returns (bool) {
        return ETTimestamp.isETWeekendByDate(_etYear, _etMonth, _etDay);
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
        return ETTimestamp.adjustedUTCForETOffset(_timestamp, _dstStart, _dstEnd);
    }

    function toUTCTimestamp(uint256 _etTimestamp, uint256 _year) external pure returns (uint256) {
        return ETTimestamp.toUTCTimestamp(_etTimestamp, _year);
    }
}
