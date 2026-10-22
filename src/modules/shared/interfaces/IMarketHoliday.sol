// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title IMarketHoliday
/// @author Robert29000
/// @notice Errors, events and external functions of the shared US market holiday module.
interface IMarketHoliday {

    /// @notice The date given to `setHolidayET` is a Saturday or a Sunday.
    error WeekendDayCannotBeSetAsHoliday();

    /// @notice Emitted when the owner sets or clears a holiday.
    /// @param year The calendar year of the ET date.
    /// @param month The month of the ET date, from 1 to 12.
    /// @param day The day of the month of the ET date.
    /// @param isHolidayET True if the date is now a holiday, false if the holiday is cleared.
    event HolidaySet(uint256 indexed year, uint256 indexed month, uint256 indexed day, bool isHolidayET);

    /// @notice Sets or clears a US market holiday on an ET calendar date.
    /// @param _year The calendar year, from 1970 to 9999.
    /// @param _month The month, from 1 to 12.
    /// @param _day The day of the month, from 1 to the number of days in the month.
    /// @param _isHolidayET True to set the date as a holiday, false to clear it.
    function setHolidayET(uint256 _year, uint256 _month, uint256 _day, bool _isHolidayET) external;

    /// @notice Returns true if the owner set the ET calendar date of a key as a holiday.
    /// @param _holidayKey The key of the date: `keccak256(abi.encode(year, month, day))`.
    /// @return True if the date is a holiday.
    function isHolidayET(bytes32 _holidayKey) external view returns (bool);
}
