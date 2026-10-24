// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UnixTimestamp } from "./UnixTimestamp.sol";

/// @title ETTimestamp
/// @author Robert29000
/// @notice US Eastern Time (ET) helpers: daylight saving time boundaries, the ET offset, UTC to ET
///         conversion and the ET calendar weekend.
/// @dev All inputs and outputs are Unix timestamps in seconds unless stated otherwise.
///      An "ET timestamp" is a UTC timestamp minus the ET offset: its UTC calendar fields (date, weekday,
///      time of day) are the ET wall-clock values. It is not a real instant; use it only for calendar math.
///      Time zone rules: EST = UTC-5, EDT = UTC-4. DST starts on the second Sunday of March at 02:00 EST
///      (07:00 UTC) and ends on the first Sunday of November at 02:00 EDT (06:00 UTC). These are the US
///      rules in force since 2007. Results for earlier years, or after a change of US law, are not correct.
///      Most functions take `dstStartTimestamp` and `dstEndTimestamp`. They must be the values that
///      `getETTransitionBoundariesInUTC` returns for the UTC year of the timestamp that is checked.
library ETTimestamp {

    /// @dev Offset of Eastern Standard Time from UTC (UTC-5), in seconds.
    uint256 constant EST_OFFSET = 5 hours;
    /// @dev Offset of Eastern Daylight Time from UTC (UTC-4), in seconds.
    uint256 constant EDT_OFFSET = 4 hours;

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
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @param dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @return True if the ET day of `_timestamp` is a Saturday or a Sunday.
    function isETWeekend(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (bool) {
        uint256 etTimestamp = toETTimestamp(_timestamp, dstStartTimestamp, dstEndTimestamp);

        return UnixTimestamp.isWeekendDay(etTimestamp);
    }

    /// @notice Returns true if an ET calendar date is a Saturday or a Sunday.
    /// @dev Use this function when the caller already has the ET date, for example from `UnixTimestamp.getDate` of an
    ///      ET timestamp. The date is already in ET, so the function does not need the DST boundaries.
    ///      Reverts with `UnixTimestamp.InvalidYear`, `UnixTimestamp.InvalidMonth` or `UnixTimestamp.InvalidDay` if the
    ///      date is not valid (see `UnixTimestamp.getTimestamp`).
    /// @param _etYear The calendar year of the ET date, from 1970 to 9999.
    /// @param _etMonth The month of the ET date, from 1 to 12.
    /// @param _etDay The day of the month of the ET date.
    /// @return True if the ET date is a Saturday or a Sunday.
    function isETWeekendByDate(uint256 _etYear, uint256 _etMonth, uint256 _etDay) internal pure returns (bool) {
        uint256 etTimestamp = UnixTimestamp.getTimestamp(_etYear, _etMonth, _etDay);
        return UnixTimestamp.isWeekendDay(etTimestamp);
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
    /// @param _timestamp Unix timestamp in seconds (UTC), calculated with the EDT offset.
    /// @param dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @return The UTC timestamp of the same ET wall-clock time under the offset in force.
    function adjustedUTCForETOffset(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (uint256) {
        if (getETOffset(_timestamp, dstStartTimestamp, dstEndTimestamp) == EST_OFFSET) {
            return _timestamp + 1 hours;
        }
        return _timestamp;
    }

    /// @notice Converts an ET timestamp to a UTC timestamp. Calculates the DST boundaries from a given year.
    /// @dev Use this overload when the caller already knows the year, to skip `UnixTimestamp.getDate`.
    ///      `_year` must be the ET year of `_etTimestamp` or the UTC year of the result. The function does not check
    ///      this: with the wrong year, the DST boundaries are wrong and the result can be off by 1 hour.
    ///      Reverts with `UnixTimestamp.InvalidYear` if `_year` is not in [1970, 9999].
    /// @param _etTimestamp ET timestamp in seconds (a UTC timestamp minus the ET offset, see `toETTimestamp`).
    /// @param _year The ET year of `_etTimestamp`, or the UTC year of the result.
    /// @return The Unix timestamp (UTC), in seconds.
    function toUTCTimestamp(uint256 _etTimestamp, uint256 _year) internal pure returns (uint256) {
        (uint256 dstStartTimestamp, uint256 dstEndTimestamp) = getETTransitionBoundariesInUTC(_year);

        return _toUTCTimestamp(_etTimestamp, dstStartTimestamp, dstEndTimestamp);
    }

    /// @notice Converts an ET timestamp to a UTC timestamp. Calculates the DST boundaries from the ET year of the
    ///         timestamp.
    /// @dev Finds the ET year with `UnixTimestamp.getDate(_etTimestamp)`. Use the overload with `_year` if the caller
    ///      already knows the year. Reverts with `UnixTimestamp.InvalidYear` if the ET year is greater than 9999.
    /// @param _etTimestamp ET timestamp in seconds (a UTC timestamp minus the ET offset, see `toETTimestamp`).
    /// @return The Unix timestamp (UTC), in seconds.
    function toUTCTimestamp(uint256 _etTimestamp) internal pure returns (uint256) {
        (uint256 year, , ) = UnixTimestamp.getDate(_etTimestamp);
        (uint256 dstStartTimestamp, uint256 dstEndTimestamp) = getETTransitionBoundariesInUTC(year);

        return _toUTCTimestamp(_etTimestamp, dstStartTimestamp, dstEndTimestamp);
    }

    /// @notice Converts an ET timestamp to a UTC timestamp.
    /// @dev Inverse of `toETTimestamp`. Adds `EDT_OFFSET`, then adds 1 more hour if EST is in force at
    ///      that instant. The EDT guess is at most 1 hour from the correct UTC instant, so it is on the correct side
    ///      of a DST boundary for every ET time except the two transition hours:
    ///      - Second Sunday of March, 02:00–02:59 ET does not exist. The result is the same instant as 03:00–03:59 EDT.
    ///      - First Sunday of November, 01:00–01:59 ET occurs twice. The first occurrence (EDT) is returned.
    ///      Market closes and reopens (20:00 ET) are never in these hours.
    /// @param _etTimestamp ET timestamp in seconds (a UTC timestamp minus the ET offset, see `toETTimestamp`).
    /// @param dstStartTimestamp DST start of the ET year of `_etTimestamp` or of the UTC year of the result.
    /// @param dstEndTimestamp DST end of the ET year of `_etTimestamp` or of the UTC year of the result.
    /// @return The Unix timestamp (UTC), in seconds.
    function _toUTCTimestamp(uint256 _etTimestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp) internal pure returns (uint256) {
        uint256 utcTimestamp = _etTimestamp + EDT_OFFSET;

        if (getETOffset(utcTimestamp, dstStartTimestamp, dstEndTimestamp) == EST_OFFSET) {
            utcTimestamp += 1 hours; // EST is in force: _etTimestamp + EST_OFFSET
        }

        return utcTimestamp;
    }
}