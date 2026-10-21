// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { StalenessChecker } from "./StalenessChecker.sol";

import { ETTimestamp } from "../libraries/ETTimestamp.sol";
import { UnixTimestamp } from "../libraries/UnixTimestamp.sol";

import { IStalenessCheckerWithHolidays } from "./interfaces/IStalenessCheckerWithHolidays.sol";

abstract contract StalenessCheckerWithHolidays is StalenessChecker, IStalenessCheckerWithHolidays {

    uint public constant MAX_REOPEN_TIME_WAIT = 4 hours;

    mapping (bytes32 => bool) public isHolidayET;

    constructor(uint256 _maxStaleness, uint256 _tradingStaleness, uint256 _reopenTimeWait) StalenessChecker(_maxStaleness, _tradingStaleness, _reopenTimeWait) {
        require(_reopenTimeWait < MAX_REOPEN_TIME_WAIT, ReopenTimeWaitGreaterThanOrEqualToMaxReopenTimeWait());
    }

    function _afterRead(RoundData memory _round) internal virtual override view {
        super._afterRead(_round);
    }

    function _checkTradingStaleness(RoundData memory _round) internal virtual override view {
        (uint256 dstStartTimestamp, uint256 dstEndTimestamp) = _getDSTBoundaries(block.timestamp);

        bool isETWeekendTrading = _isETWeekendTrading(block.timestamp, dstStartTimestamp, dstEndTimestamp, reopenTimeWait);
        bool isETHolidayTrading = _isETHolidayTrading(block.timestamp, dstStartTimestamp, dstEndTimestamp, reopenTimeWait);

        if (!(isETWeekendTrading || isETHolidayTrading)) {
            revert TradingStalenessReached();
        } else {
            uint etTimestamp = ETTimestamp.toETTimestamp(block.timestamp, dstStartTimestamp, dstEndTimestamp);
            (uint256 year, uint256 month, uint256 day) = UnixTimestamp.getDate(etTimestamp);

            DayType dayType = DayType.Regular;

            if (UnixTimestamp.isWeekendDay(etTimestamp)) {
                dayType = DayType.Weekend;
            } else if (_checkIsHolidayET(year, month, day)) {
                dayType = DayType.Holiday;
            } else {
                dayType = DayType.Regular;
            }

            uint256 lastETCloseTimestampInUTC = _getLastETCloseTimestampInUTC(year, month, day, dayType);
            require(_round.updatedAt + tradingStaleness >= lastETCloseTimestampInUTC, TradingStalenessReached());
        }
    }

    function _isETHolidayTrading(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp, uint256 _reopenTimeWait) internal view returns (bool) {
        uint etTimestamp = ETTimestamp.toETTimestamp(_timestamp, dstStartTimestamp, dstEndTimestamp);

        (uint256 year, uint256 month, uint256 day) = UnixTimestamp.getDate(etTimestamp);
        (uint256 nextYear, uint256 nextMonth, uint256 nextDay) = UnixTimestamp.getNextDate(year, month, day);

        bool isCurrentDateHoliday = _checkIsHolidayET(year, month, day);
        bool isNextDateHoliday = _checkIsHolidayET(nextYear, nextMonth, nextDay);

        uint256 secondsOfDay = etTimestamp % 1 days;

        if (secondsOfDay < 20 hours) {
            return isCurrentDateHoliday;                                   // inside today's session
        }
        return isNextDateHoliday                                           // tomorrow's session is closed
            || (isCurrentDateHoliday && secondsOfDay < 20 hours + _reopenTimeWait); // grace after today's reopen
    }

    function _getLastETCloseTimestampInUTC(uint256 _year, uint256 _month, uint256 _day, DayType _dayType) internal view returns (uint256) {
        if (_dayType == DayType.Weekend) {

            uint prevYear = _year;
            uint prevMonth = _month;
            uint prevDay = _day;

            uint256 etTimestamp = UnixTimestamp.getTimestamp(prevYear, prevMonth, prevDay);

            if (UnixTimestamp.getWeekday(etTimestamp) == 6) {
                (prevYear, prevMonth, prevDay) = UnixTimestamp.getPrevDate(prevYear, prevMonth, prevDay);
            }

            (prevYear, prevMonth, prevDay) = UnixTimestamp.getPrevDate(prevYear, prevMonth, prevDay);

            if (!_checkIsHolidayET(prevYear, prevMonth, prevDay)) {

                uint256 etPrevTimestamp = UnixTimestamp.getTimestamp(prevYear, prevMonth, prevDay) + 20 hours;

                return ETTimestamp.toUTCTimestamp(etPrevTimestamp, prevYear);
            } else {

                return _getLastETCloseTimestampInUTC(prevYear, prevMonth, prevDay, DayType.Holiday);
            }
        } else if (_dayType == DayType.Holiday) {

            uint prevYear = _year;
            uint prevMonth = _month;
            uint prevDay = _day;
            DayType prevDayType = DayType.Regular;

            (prevYear, prevMonth, prevDay) = UnixTimestamp.getPrevDate(prevYear, prevMonth, prevDay);
            uint256 etPrevTimestamp = UnixTimestamp.getTimestamp(prevYear, prevMonth, prevDay);

            if (UnixTimestamp.isWeekendDay(etPrevTimestamp)) {

                prevDayType = DayType.Weekend;
            } else if (_checkIsHolidayET(prevYear, prevMonth, prevDay)) {

                prevDayType = DayType.Holiday;
            } else {

                return ETTimestamp.toUTCTimestamp(etPrevTimestamp + 20 hours, prevYear);
            }

            return _getLastETCloseTimestampInUTC(prevYear, prevMonth, prevDay, prevDayType);
        } else {
            uint256 etTimestamp = UnixTimestamp.getTimestamp(_year, _month, _day);

            return ETTimestamp.toUTCTimestamp(etTimestamp + 20 hours, _year);
        }
    }

    function _checkIsHolidayET(uint256 _year, uint256 _month, uint256 _day) internal view returns (bool) {
        bytes32 holidayKey = _getHolidayKey(_year, _month, _day);
        return isHolidayET[holidayKey];
    }

    function setHolidayET(uint256 _year, uint256 _month, uint256 _day, bool _isHolidayET) external onlyOwner {

        uint256 etTimestamp = UnixTimestamp.getTimestamp(_year, _month, _day);

        if (UnixTimestamp.isWeekendDay(etTimestamp)) {
            revert WeekendDayCannotBeSetAsHoliday();
        }

        bytes32 holidayKey = _getHolidayKey(_year, _month, _day);
        isHolidayET[holidayKey] = _isHolidayET;

        emit HolidaySet(_year, _month, _day, _isHolidayET);
    }

    function _getHolidayKey(uint256 _year, uint256 _month, uint256 _day) internal pure returns (bytes32) {
        return keccak256(abi.encode(_year, _month, _day));
    }
}