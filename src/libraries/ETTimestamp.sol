// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UnixTimestamp } from "./UnixTimestamp.sol";

/// @title ETTimestamp
/// @author Robert29000
/// @notice US Eastern Time (ET) helpers for the US stock market weekly schedule: daylight saving
///         time boundaries, UTC to ET conversion and the weekend closure (Friday 20:00 ET to Sunday 20:00 ET).
/// @dev All inputs and outputs are Unix timestamps in seconds unless stated otherwise.
///      An "ET timestamp" is a UTC timestamp minus the ET offset: its UTC calendar fields (date, weekday,
///      time of day) are the ET wall-clock values. It is not a real instant; use it only for calendar math.
///      Time zone rules: EST = UTC-5, EDT = UTC-4. DST starts on the second Sunday of March at 02:00 EST
///      (07:00 UTC) and ends on the first Sunday of November at 02:00 EDT (06:00 UTC). These are the US
///      rules in force since 2007. Results for earlier years, or after a change of US law, are not correct.
///      Most functions take `dstStartTimestamp` and `dstEndTimestamp`. They must be the values that
///      `getETTransitionBoundariesInUTC` returns for the UTC year of the timestamp that is checked.
///      The library assumes a 24/5 trading week with a Friday 20:00 ET close and a Sunday 20:00 ET reopen.
///      US market holidays and early closes are not handled.
library ETTimestamp {

    /// @dev Offset of Eastern Standard Time from UTC (UTC-5), in seconds.
    uint256 constant EST_OFFSET = 5 hours;
    /// @dev Offset of Eastern Daylight Time from UTC (UTC-4), in seconds.
    uint256 constant EDT_OFFSET = 4 hours;

    /// @dev Weekday number of Saturday in `UnixTimestamp.getWeekday` (Monday = 0).
    uint256 constant SATURDAY = 5; // Monday = 0


    /// @dev Weekly market close: Friday 20:00 ET, as seconds after Monday 00:00 ET.
    uint256 constant FRIDAY_CLOSE  = 4 days + 20 hours; // Friday 20:00
    /// @dev Weekly market reopen: Sunday 20:00 ET, as seconds after Monday 00:00 ET.
    uint256 constant SUNDAY_REOPEN = 6 days + 20 hours; // Sunday 20:00
    /// @dev Length of one week, in seconds.
    uint256 constant WEEK = 7 days;

    /// @notice Returns the UTC timestamps when US daylight saving time starts and ends in a year.
    /// @dev Reverts with `UnixTimestamp.InvalidYear` if `_year` is not in [1970, 9999].
    ///      The US rules in force since 2007 are applied to every year.
    /// @param _year The calendar year, from 1970 to 9999.
    /// @return Unix timestamp of the DST start: second Sunday of March, 02:00 EST (07:00 UTC).
    /// @return Unix timestamp of the DST end: first Sunday of November, 02:00 EDT (06:00 UTC).
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
        dstStartTimestamp += 7 hours;  // Second Sunday in March, 07:00 UTC (02:00 EST)
        
        // DST ends on the first Sunday in November
        uint256 dstEndMonth = 11;
        uint256 dstEndDay = 1;

        uint256 dstEndTimestamp = UnixTimestamp.getTimestamp(_year, dstEndMonth, dstEndDay);
        uint256 dstEndWeekday = UnixTimestamp.getWeekday(dstEndTimestamp);

        if (dstEndWeekday < 6) {
            dstEndDay += 6 - dstEndWeekday;
            dstEndTimestamp = UnixTimestamp.getTimestamp(_year, dstEndMonth, dstEndDay);
        }

        dstEndTimestamp += 6 hours; // First Sunday in November, 06:00 UTC (02:00 EDT)

        return (dstStartTimestamp, dstEndTimestamp);
    }

    /// @notice Returns true if the ET calendar day of a timestamp is a Saturday or a Sunday.
    /// @dev This is the calendar weekend (Saturday 00:00 ET to Monday 00:00 ET), not the market closure.
    ///      For the market closure use `isETWeekendTrading`.
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @param dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @return True if the ET day of `_timestamp` is a Saturday or a Sunday.
    function isETWeekend(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (bool) {
        uint256 etTimestamp = toETTimestamp(_timestamp, dstStartTimestamp, dstEndTimestamp);

        return UnixTimestamp.isWeekendDay(etTimestamp);
    }

    /// @notice Returns true if a timestamp is in the weekend market closure (Friday 20:00 ET to Sunday 20:00 ET).
    /// @dev Same as the 4-argument overload with a grace period of zero. The interval includes the close and
    ///      excludes the reopen.
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @param dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @return True if the market is closed for the weekend at `_timestamp`.
    function isETWeekendTrading(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (bool) {
        uint256 etTimestamp = toETTimestamp(_timestamp, dstStartTimestamp, dstEndTimestamp);

        return _checkETWeekendTrading(etTimestamp, 0);
    }

    /// @notice Returns true if a timestamp is in the weekend market closure (Friday 20:00 ET to Sunday 20:00 ET),
    ///         or less than `_gracePeriodOffset` seconds after the Sunday 20:00 ET reopen.
    /// @dev The grace period can continue into Monday and later days of the week.
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @param dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @param _gracePeriodOffset Grace period after the Sunday 20:00 ET reopen, in seconds.
    /// @return True if the market is closed for the weekend, or the reopen grace period is not over, at `_timestamp`.
    function isETWeekendTrading(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp, uint256 _gracePeriodOffset) internal pure returns (bool) {
        uint256 etTimestamp = toETTimestamp(_timestamp, dstStartTimestamp, dstEndTimestamp);

        return _checkETWeekendTrading(etTimestamp, _gracePeriodOffset);
    }

    /// @notice Returns true if an ET timestamp is in the weekend closure or in the grace period after the reopen.
    /// @dev Calculates the position in the ET week (seconds after Monday 00:00 ET) and compares it with
    ///      `FRIDAY_CLOSE` and `SUNDAY_REOPEN`. If `_gracePeriod` is `WEEK - SUNDAY_REOPEN + FRIDAY_CLOSE` (the time from the
    ///      reopen to the next close) or more, the result is true for the whole week.
    /// @param _etTimestamp ET timestamp in seconds (a UTC timestamp minus the ET offset, see `toETTimestamp`).
    /// @param _gracePeriod Grace period after the Sunday 20:00 ET reopen, in seconds.
    /// @return True if the market is closed for the weekend, or the reopen grace period is not over.
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

    /// @notice Returns the UTC timestamp of the last Friday 20:00 ET market close at or before a timestamp.
    /// @dev Friday 20:00 ET is Saturday 00:00 UTC under EDT and Saturday 01:00 UTC under EST. The function
    ///      finds the start of the last UTC Saturday at or before `_timestamp`, applies the ET offset in force at
    ///      that instant, and goes back one week if the result is after `_timestamp`.
    ///      Reverts on underflow if `_timestamp` is before 1970-01-03 01:00 UTC (the first Friday 20:00 EST close
    ///      after the Unix epoch). This does not affect current timestamps.
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @param dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @return UTC timestamp of the most recent Friday 20:00 ET close at or before `_timestamp`.
    function getLastETFridayCloseInUTC(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (uint256) {
        uint256 daysSinceSaturday = (UnixTimestamp.getWeekday(_timestamp) + 7 - SATURDAY) % 7;
        uint256 saturdayUTC = _timestamp - _timestamp % 1 days - daysSinceSaturday * 1 days;

        uint256 closeUTC = _adjustedUTCForETOffset(saturdayUTC, dstStartTimestamp, dstEndTimestamp);

        if (closeUTC > _timestamp) {
            closeUTC = _adjustedUTCForETOffset(saturdayUTC - WEEK, dstStartTimestamp, dstEndTimestamp);
        }

        return closeUTC;
    }

    /// @notice Returns the ET offset from UTC in force at a timestamp.
    /// @dev Returns `EDT_OFFSET` if `dstStartTimestamp <= _timestamp < dstEndTimestamp`, else `EST_OFFSET`.
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @param dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @return The offset in seconds: `EDT_OFFSET` or `EST_OFFSET`.
    function getETOffset(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (uint256) {
        if (_timestamp >= dstStartTimestamp && _timestamp < dstEndTimestamp) {
            return EDT_OFFSET;
        } else {
            return EST_OFFSET;
        }
    }

    /// @notice Converts a UTC timestamp to an ET timestamp.
    /// @dev The result is `_timestamp` minus the ET offset in force at `_timestamp`. Its UTC calendar fields are the
    ///      ET wall-clock values. Reverts on underflow if `_timestamp` is less than the offset.
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @param dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @return The ET timestamp, in seconds.
    function toETTimestamp(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (uint256) {
        uint256 offset = getETOffset(_timestamp, dstStartTimestamp, dstEndTimestamp);
        return _timestamp - offset;
    }

    /// @notice Moves a UTC instant calculated with the EDT offset to the same ET wall-clock time under EST, if EST is in force.
    /// @dev Adds 1 hour if `getETOffset(_timestamp)` is `EST_OFFSET`, else returns `_timestamp` unchanged.
    ///      Used to convert Saturday 00:00 UTC (Friday 20:00 EDT) to Friday 20:00 ET.
    /// @param _timestamp Unix timestamp in seconds (UTC), calculated with the EDT offset.
    /// @param dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @return The UTC timestamp of the same ET wall-clock time under the offset in force.
    function _adjustedUTCForETOffset(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (uint256) {
        if (getETOffset(_timestamp, dstStartTimestamp, dstEndTimestamp) == EST_OFFSET) {
            return _timestamp + 1 hours;
        }
        return _timestamp;
    }
}