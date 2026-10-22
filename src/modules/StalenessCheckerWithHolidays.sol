// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { StalenessChecker } from "./StalenessChecker.sol";

import { ETTimestamp } from "../libraries/ETTimestamp.sol";
import { UnixTimestamp } from "../libraries/UnixTimestamp.sol";

import { IStalenessCheckerWithHolidays } from "./interfaces/IStalenessCheckerWithHolidays.sol";

/// @title StalenessCheckerWithHolidays
/// @author Robert29000
/// @notice Staleness module that also accepts older prices while the US market is closed for a holiday.
///         It extends the weekend rules of `StalenessChecker`. The owner sets each holiday as an ET calendar date.
/// @dev Market model: the market trades 24 hours a day, 5 days a week. The session of a weekday D starts at
///      20:00 ET on the day before D and ends at 20:00 ET on D. A holiday on D closes the market for this session.
///      A grace period of `reopenTimeWait` seconds follows the reopen at 20:00 ET on D.
///      Overrides `_checkTradingStaleness`. A price older than `tradingStaleness` is accepted only if both are true:
///      - `block.timestamp` is in the weekend closure or its reopen grace period (`_isETWeekendTrading`), or in a
///        holiday closure or its reopen grace period (`_isETHolidayTrading`).
///      - The price was fresh at the last market close before the closure (`_getLastETCloseTimestampInUTC`):
///        `updatedAt + tradingStaleness >= lastClose`. The search for the last close skips weekends and holidays.
///      Otherwise it reverts with `TradingStalenessReached`.
///      `reopenTimeWait` must be less than `MAX_REOPEN_TIME_WAIT`, so each grace period ends before 00:00 ET of the
///      next day. Early closes (half days) are not handled: the module always uses the 20:00 ET close.
///      Trust assumption: the owner sets the holidays correctly and before they occur. If a holiday is not set, reads
///      revert during the holiday closure. If a date is set by mistake, the module accepts older prices on that date.
abstract contract StalenessCheckerWithHolidays is StalenessChecker, IStalenessCheckerWithHolidays {

    /// @notice Exclusive upper bound of `reopenTimeWait`, in seconds. The grace period after a 20:00 ET reopen must
    ///         end before 00:00 ET of the next day.
    uint public constant MAX_REOPEN_TIME_WAIT = 4 hours;

    /// @notice Returns true if the owner set the ET calendar date of a key as a holiday.
    /// @dev The key is `_getHolidayKey(year, month, day)`: `keccak256(abi.encode(year, month, day))`.
    ///      This NatSpec is explicit (not inherited from the interface), because `forge doc` does not show
    ///      inherited NatSpec for a mapping.
    mapping (bytes32 => bool) public isHolidayET;

    /// @notice Sets the staleness limits. The limits cannot be changed after deployment.
    /// @dev Runs the `StalenessChecker` constructor checks first. Then reverts with
    ///      `ReopenTimeWaitGreaterThanOrEqualToMaxReopenTimeWait` if `_reopenTimeWait >= MAX_REOPEN_TIME_WAIT`.
    /// @param _maxStaleness Maximum age of the price at any time, in seconds.
    /// @param _tradingStaleness Maximum age of the price while the market trades, in seconds.
    /// @param _reopenTimeWait Grace period after the Sunday 20:00 ET reopen and after each 20:00 ET reopen on a
    ///        holiday, in seconds. Can be zero.
    constructor(uint256 _maxStaleness, uint256 _tradingStaleness, uint256 _reopenTimeWait) StalenessChecker(_maxStaleness, _tradingStaleness, _reopenTimeWait) {
        require(_reopenTimeWait < MAX_REOPEN_TIME_WAIT, ReopenTimeWaitGreaterThanOrEqualToMaxReopenTimeWait());
    }

    /// @inheritdoc StalenessChecker
    /// @dev Calls `super._afterRead(_round)`. `StalenessChecker._afterRead` calls the `_checkTradingStaleness`
    ///      override of this contract.
    function _afterRead(RoundData memory _round) internal virtual override view {
        super._afterRead(_round);
    }

    /// @notice Checks if a price older than `tradingStaleness` can be accepted because the market is closed for a
    ///         weekend or a holiday.
    /// @dev `_afterRead` calls this function only if `_round.updatedAt + tradingStaleness < block.timestamp`.
    ///      `maxStaleness` is already checked. Reverts with `TradingStalenessReached` if one of these is true:
    ///      - `block.timestamp` is not in the weekend closure, not in a holiday closure and not in a reopen grace
    ///        period (`_isETWeekendTrading`, `_isETHolidayTrading`).
    ///      - The price was already older than `tradingStaleness` at the last market close:
    ///        `_round.updatedAt + tradingStaleness < lastClose` (`_getLastETCloseTimestampInUTC`).
    ///      The search for the last close starts from the ET date of `block.timestamp`. A Saturday or a Sunday is
    ///      `Weekend`, a holiday is `Holiday` and any other day is `Regular`.
    ///      Reverts with `UnixTimestamp.InvalidYear` if the ET year of `block.timestamp` is 9999 or greater.
    /// @param _round The round data returned by `aggregator.latestRoundData()`.
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

    /// @notice Returns true if a timestamp is in a holiday closure, or less than `_reopenTimeWait` seconds after the
    ///         20:00 ET reopen on a holiday.
    /// @dev With `t` the ET time of day of `_timestamp`:
    ///      - Before 20:00 ET: true if the ET date of `_timestamp` is a holiday.
    ///      - At or after 20:00 ET: true if the next ET date is a holiday, or if the ET date is a holiday and
    ///        `t < 20:00 + _reopenTimeWait`.
    ///      This function does not check weekends. `_isETWeekendTrading` checks them.
    ///      Reverts with `UnixTimestamp.InvalidYear` if the ET year of `_timestamp` is 9999 or greater
    ///      (`UnixTimestamp.getNextDate`).
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @param dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @param _reopenTimeWait Grace period after the 20:00 ET reopen on a holiday, in seconds. The grace period
    ///        ends at 00:00 ET at the latest.
    /// @return True if the market is closed for a holiday, or the holiday reopen grace period is not over, at `_timestamp`.
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

    /// @notice Returns the UTC timestamp of the last 20:00 ET market close before the closure that contains an ET date.
    /// @dev Starts from the ET date `_year`-`_month`-`_day` and its `_dayType`:
    ///      - `Regular`: returns 20:00 ET on the date. `_checkTradingStaleness` gets this case only at or after
    ///        20:00 ET on the day before a holiday.
    ///      - `Weekend`: goes back to the Friday before the date. If that Friday is a holiday, continues as `Holiday`
    ///        from the Friday. Else returns 20:00 ET on the Friday.
    ///      - `Holiday`: goes back one day. If that day is a weekend day or a holiday, continues as `Weekend` or
    ///        `Holiday` from that day. Else returns 20:00 ET on that day.
    ///      The function calls itself one time for each weekend or holiday in the chain.
    ///      20:00 ET is never in a DST transition hour, so the conversion to UTC is exact.
    ///      Reverts with `UnixTimestamp.InvalidYear` if the search gets to a date in 1970 (`UnixTimestamp.getPrevDate`).
    /// @param _year The calendar year of the ET date.
    /// @param _month The month of the ET date, from 1 to 12.
    /// @param _day The day of the month of the ET date.
    /// @param _dayType The type of the ET date: `Regular`, `Holiday` or `Weekend`.
    /// @return UTC timestamp of 20:00 ET on the last trading day: the date itself for `Regular`, an earlier date for
    ///         `Holiday` and `Weekend`.
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

    /// @notice Returns true if the owner set an ET calendar date as a holiday.
    /// @param _year The calendar year of the ET date.
    /// @param _month The month of the ET date, from 1 to 12.
    /// @param _day The day of the month of the ET date.
    /// @return True if the date is a holiday.
    function _checkIsHolidayET(uint256 _year, uint256 _month, uint256 _day) internal view returns (bool) {
        bytes32 holidayKey = _getHolidayKey(_year, _month, _day);
        return isHolidayET[holidayKey];
    }

    /// @inheritdoc IStalenessCheckerWithHolidays
    /// @dev Only the owner can call this function. Reverts with `UnixTimestamp.InvalidYear`, `UnixTimestamp.InvalidMonth`
    ///      or `UnixTimestamp.InvalidDay` if the date is not valid, and with `WeekendDayCannotBeSetAsHoliday` if the
    ///      date is a Saturday or a Sunday. It does not check that the date is in the future, and it accepts the
    ///      current value again. Emits `HolidaySet`.
    function setHolidayET(uint256 _year, uint256 _month, uint256 _day, bool _isHolidayET) external onlyOwner {

        uint256 etTimestamp = UnixTimestamp.getTimestamp(_year, _month, _day);

        if (UnixTimestamp.isWeekendDay(etTimestamp)) {
            revert WeekendDayCannotBeSetAsHoliday();
        }

        bytes32 holidayKey = _getHolidayKey(_year, _month, _day);
        isHolidayET[holidayKey] = _isHolidayET;

        emit HolidaySet(_year, _month, _day, _isHolidayET);
    }

    /// @notice Returns the key of an ET calendar date in `isHolidayET`.
    /// @dev The key is `keccak256(abi.encode(_year, _month, _day))`. This function does not validate the date.
    /// @param _year The calendar year of the ET date.
    /// @param _month The month of the ET date, from 1 to 12.
    /// @param _day The day of the month of the ET date.
    /// @return The key of the date.
    function _getHolidayKey(uint256 _year, uint256 _month, uint256 _day) internal pure returns (bytes32) {
        return keccak256(abi.encode(_year, _month, _day));
    }
}