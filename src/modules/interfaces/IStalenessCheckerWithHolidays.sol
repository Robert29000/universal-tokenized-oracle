// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title IStalenessCheckerWithHolidays
/// @author Robert29000
/// @notice Types, errors, events and external functions of the staleness module with US market holidays.
interface IStalenessCheckerWithHolidays {

    /// @notice Type of an ET calendar day, used to find the last market close.
    /// @dev - `Regular`: a weekday that is not a holiday. The market closes at 20:00 ET.
    ///      - `Holiday`: a weekday that the owner set as a holiday. The market is closed for the full session.
    ///      - `Weekend`: a Saturday or a Sunday.
    enum DayType {
        Regular,
        Holiday,
        Weekend
    }

    /// @notice The reopen time wait given to the constructor is greater than or equal to `MAX_REOPEN_TIME_WAIT`.
    error ReopenTimeWaitGreaterThanOrEqualToMaxReopenTimeWait();
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
