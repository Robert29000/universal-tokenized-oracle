// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { IMarketHoliday } from "./interfaces/IMarketHoliday.sol";

import { ETTimestamp } from "../../libraries/ETTimestamp.sol";
import { UnixTimestamp } from "../../libraries/UnixTimestamp.sol";

/// @title MarketHoliday
/// @author Robert29000
/// @notice Shared module that stores the US market holidays. The owner sets each holiday as an ET calendar date.
///         Modules that need the holidays inherit this contract, so all of them read the same dates.
/// @dev Market model: the market trades 24 hours a day, 5 days a week. The session of a weekday D starts at
///      20:00 ET on the day before D and ends at 20:00 ET on D. A holiday on D closes the market for this session.
///      Trust assumption: the owner sets the holidays correctly and before they occur. The effect of a missing or
///      wrong date is described in each module that reads the holidays.
abstract contract MarketHoliday is Ownable, IMarketHoliday {

    /// @notice Returns true if the owner set the ET calendar date of a key as a holiday.
    /// @dev The key is `_getHolidayKey(year, month, day)`: `keccak256(abi.encode(year, month, day))`.
    ///      This NatSpec is explicit (not inherited from the interface), because `forge doc` does not show
    ///      inherited NatSpec for a mapping.
    mapping (bytes32 => bool) public isHolidayET;

    /// @inheritdoc IMarketHoliday
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

    /// @notice Returns true if a timestamp is in a holiday closure, or less than `_reopenTimeWait` seconds after the
    ///         20:00 ET reopen on a holiday.
    /// @dev With `t` the ET time of day of `_timestamp`:
    ///      - Before 20:00 ET: true if the ET date of `_timestamp` is a holiday.
    ///      - At or after 20:00 ET: true if the next ET date is a holiday, or if the ET date is a holiday and
    ///        `t < 20:00 + _reopenTimeWait`.
    ///      This function does not check weekends. `StalenessChecker._isETWeekendTrading` checks them.
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

    /// @notice Returns true if the owner set an ET calendar date as a holiday.
    /// @param _year The calendar year of the ET date.
    /// @param _month The month of the ET date, from 1 to 12.
    /// @param _day The day of the month of the ET date.
    /// @return True if the date is a holiday.
    function _checkIsHolidayET(uint256 _year, uint256 _month, uint256 _day) internal view returns (bool) {
        bytes32 holidayKey = _getHolidayKey(_year, _month, _day);
        return isHolidayET[holidayKey];
    }
}
