// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UnixTimestamp } from "./UnixTimestamp.sol";

library ETTimestamp {

    uint256 constant EST_OFFSET = 5 hours;
    uint256 constant EDT_OFFSET = 4 hours;

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
        uint offest = getETOffset(_timestamp, dstStartTimestamp, dstEndTimestamp);
        uint256 etTimestamp = _timestamp - offest;

        return UnixTimestamp.isWeekendDay(etTimestamp);
    }

    function isETWeekendTrading(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (bool) {
        uint offest = getETOffset(_timestamp, dstStartTimestamp, dstEndTimestamp);
        uint256 etTimestamp = _timestamp - offest;

        uint256 weekDay = UnixTimestamp.getWeekday(etTimestamp);

        if (weekDay < 4) {
            return false;
        } else if (weekDay == 5) {
            return true;
        } else if (weekDay == 4) {
            return UnixTimestamp.getHour(etTimestamp) >= 20;
        } else {
            return UnixTimestamp.getHour(etTimestamp) < 20;
        }
    }

    function getETOffset(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (uint256) {
        if (_timestamp >= dstStartTimestamp && _timestamp < dstEndTimestamp) {
            return EDT_OFFSET;
        } else {
            return EST_OFFSET;
        }
    }

}