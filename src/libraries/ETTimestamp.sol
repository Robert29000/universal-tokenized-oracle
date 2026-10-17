// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UnixTimestamp } from "./UnixTimestamp.sol";

library ETTimestamp {

    uint256 constant EST_OFFSET = 5 hours;
    uint256 constant EDT_OFFSET = 4 hours;

    uint256 constant FRIDAY_CLOSE  = 4 days + 20 hours; // Friday 20:00
    uint256 constant SUNDAY_REOPEN = 6 days + 20 hours; // Sunday 20:00
    uint256 constant WEEK          = 7 days;

    function getETTransitionBoundariesInUTC(uint256 _year) internal pure returns (uint256, uint256) {

        // DST starts on the second Sunday in March
        uint256 dstStartMonth = 3;
        uint256 dstStartDay = 1;

        uint256 dstStartTimestamp = UnixTimestamp.getTimestamp(_year, dstStartMonth, dstStartDay);
        uint256 dstStartWeekday = UnixTimestamp.getWeekday(dstStartTimestamp);

        if (dstStartWeekday < 6) {
            dstStartDay += 6 - dstStartWeekday;
        }

        // At this point, dstStartDay is the first Sunday in March
        dstStartDay += 7;

        dstStartTimestamp = UnixTimestamp.getTimestamp(_year, dstStartMonth, dstStartDay);
        dstStartTimestamp += 7 hours;  // Second Sunday in March, 07:00 UTC 
        
        // DST ends on the first Sunday in November
        uint256 dstEndMonth = 11;
        uint256 dstEndDay = 1;

        uint256 dstEndTimestamp = UnixTimestamp.getTimestamp(_year, dstEndMonth, dstEndDay);
        uint256 dstEndWeekday = UnixTimestamp.getWeekday(dstEndTimestamp);

        if (dstEndWeekday < 6) {
            dstEndDay += 6 - dstEndWeekday;
            dstEndTimestamp = UnixTimestamp.getTimestamp(_year, dstEndMonth, dstEndDay);
        }

        dstEndTimestamp += 6 hours; // First Sunday in November, 06:00 UTC 

        return (dstStartTimestamp, dstEndTimestamp);
    }

    function isETWeekend(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (bool) {
        uint256 etTimestamp = toETTimestamp(_timestamp, dstStartTimestamp, dstEndTimestamp);

        return UnixTimestamp.isWeekendDay(etTimestamp);
    }

    function isETWeekendTrading(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (bool) {
        uint256 etTimestamp = toETTimestamp(_timestamp, dstStartTimestamp, dstEndTimestamp);

        return _checkETWeekendTrading(etTimestamp, 0);
    }

    function isETWeekendTrading(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp, uint256 _gracePeriodOffset) internal pure returns (bool) {
        uint256 etTimestamp = toETTimestamp(_timestamp, dstStartTimestamp, dstEndTimestamp);

        return _checkETWeekendTrading(etTimestamp, _gracePeriodOffset);
    }

    function _checkETWeekendTrading(uint256 _etTimestamp, uint256 _gracePeriod) internal pure returns (bool) {
        // Seconds elapsed since Monday 00:00 ET of the current week
        uint256 secondsIntoWeek = UnixTimestamp.getWeekday(_etTimestamp) * 1 days + _etTimestamp % 1 days;

        // Monday 00:00 – Friday 20:00: market open, unless last Sunday's grace period is still running
        if (secondsIntoWeek < FRIDAY_CLOSE) {
            uint256 sinceLastReopen = secondsIntoWeek + (WEEK - SUNDAY_REOPEN);
            return sinceLastReopen < _gracePeriod;
        }

        // Friday 20:00 – Sunday 20:00: market closed
        if (secondsIntoWeek < SUNDAY_REOPEN) {
            return true;
        }

        // Sunday 20:00 – Monday 00:00: market reopened, grace period may still be running
        uint256 sinceReopen = secondsIntoWeek - SUNDAY_REOPEN;
        return sinceReopen < _gracePeriod;
    }

    function getETOffset(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (uint256) {
        if (_timestamp >= dstStartTimestamp && _timestamp < dstEndTimestamp) {
            return EDT_OFFSET;
        } else {
            return EST_OFFSET;
        }
    }

    function toETTimestamp(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (uint256) {
        uint256 offset = getETOffset(_timestamp, dstStartTimestamp, dstEndTimestamp);
        return _timestamp - offset;
    }

}