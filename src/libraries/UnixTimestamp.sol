// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title UnixTimestamp
/// @author Robert29000
/// @notice Converts between Unix timestamps and proleptic Gregorian calendar dates, and returns the day of the week.
/// @dev All timestamps are in seconds since 1970-01-01 00:00:00 UTC. The library does not apply any
///      time zone: the date and weekday are those of the UTC day of the timestamp.
///      The conversions use the `civil_from_days` and `days_from_civil` algorithms of Howard Hinnant.
///      Weekdays are numbered Monday = 0 to Sunday = 6.
library UnixTimestamp {

    /// @notice The year is less than 1970 or greater than 9999.
    error InvalidYear();
    /// @notice The month is less than 1 or greater than 12.
    error InvalidMonth();
    /// @notice The day is less than 1 or greater than the number of days in the month.
    error InvalidDay();

    /// @notice Returns the UTC calendar date of a Unix timestamp.
    /// @dev Valid for all `uint256` timestamps that do not overflow the intermediate arithmetic
    ///      (all practical values). The time of day is ignored.
    /// @param _timestamp Unix timestamp in seconds.
    /// @return year The calendar year (for example 2026).
    /// @return month The month, from 1 (January) to 12 (December).
    /// @return day The day of the month, from 1 to 31.
    function getDate(uint256 _timestamp) internal pure returns (uint256 year, uint256 month, uint256 day) {
        uint256 z = _timestamp / 86400;
        uint256 z_offset = z + 719468;

        uint256 era = z_offset / 146097;
        uint256 doe = z_offset - era * 146097;

        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;

        uint256 doy = doe - (yoe * 365 + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;

        day = doy - (mp * 153 + 2) / 5 + 1;

        month = mp < 10 ? mp + 3 : mp - 9;

        year = era * 400 + yoe;
        year += month <= 2 ? 1 : 0;
    }


    /// @notice Returns the Unix timestamp of 00:00:00 UTC on a calendar date.
    /// @dev Reverts with `InvalidYear` if `_year` is not in [1970, 9999], `InvalidMonth` if `_month` is not
    ///      in [1, 12], and `InvalidDay` if `_day` is not in [1, `_daysInMonth(_year, _month)`].
    /// @param _year The calendar year, from 1970 to 9999.
    /// @param _month The month, from 1 to 12.
    /// @param _day The day of the month, from 1 to the number of days in the month.
    /// @return Unix timestamp in seconds of the start (00:00:00 UTC) of the date.
    function getTimestamp(uint256 _year, uint256 _month, uint256 _day) internal pure returns (uint256) {
        require(_year >= 1970 && _year <= 9999, InvalidYear());
        require(_month >= 1 && _month <= 12, InvalidMonth());
        require(_day >= 1 && _day <= _daysInMonth(_year, _month), InvalidDay());

        uint256 y = _year - (_month <= 2 ? 1 : 0);

        uint256 era = y / 400;
        uint256 yoe = y - era * 400;

        uint256 mp = _month > 2 ? _month - 3 : _month + 9;
        uint256 doy = (153 * mp + 2) / 5 + _day - 1;

        uint256 doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;

        uint256 daysSinceEpoch = era * 146097 + doe - 719468;

        return daysSinceEpoch * 1 days;
    }

    /// @notice Returns true if the UTC day of a timestamp is a Saturday or a Sunday.
    /// @param _timestamp Unix timestamp in seconds.
    /// @return True if the weekday of `_timestamp` is Saturday (5) or Sunday (6).
    function isWeekendDay(uint256 _timestamp) internal pure returns (bool) {
        return getWeekday(_timestamp) >= 5;
    }

    /// @notice Returns the day of the week of the UTC day of a timestamp.
    /// @dev 1970-01-01 was a Thursday, so the result is `(days since epoch + 3) % 7`.
    /// @param _timestamp Unix timestamp in seconds.
    /// @return The weekday, from 0 (Monday) to 6 (Sunday).
    function getWeekday(uint256 _timestamp) internal pure returns (uint256) {
        return (_timestamp / 86400 + 3) % 7;
    }

    /// @notice Returns the number of days in a month of the proleptic Gregorian calendar.
    /// @dev Does not validate its inputs: any `_month` other than 2, 4, 6, 9 or 11 returns 31.
    ///      `getTimestamp` checks `_month` before calling it.
    /// @param _year The calendar year, used only for February.
    /// @param _month The month, from 1 to 12.
    /// @return The number of days in the month: 28 to 31.
    function _daysInMonth(uint256 _year, uint256 _month) internal pure returns (uint256) {
        if (_month == 2) {
            return _isLeapYear(_year) ? 29 : 28;
        }
        if (_month == 4 || _month == 6 || _month == 9 || _month == 11) {
            return 30;
        }
        return 31;
    }

    /// @notice Returns true if a year is a leap year in the proleptic Gregorian calendar.
    /// @dev A year is a leap year if it is divisible by 4 and not by 100, or if it is divisible by 400.
    /// @param _year The calendar year.
    /// @return True if `_year` has 366 days.
    function _isLeapYear(uint256 _year) internal pure returns (bool) {
        return (_year % 4 == 0 && _year % 100 != 0) || _year % 400 == 0;
    }
}