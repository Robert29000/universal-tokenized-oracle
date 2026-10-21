// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IStalenessCheckerWithHolidays {

    enum DayType {
        Regular,
        Holiday,
        Weekend
    }

    error ReopenTimeWaitGreaterThanOrEqualToMaxReopenTimeWait();
    error WeekendDayCannotBeSetAsHoliday();

    event HolidaySet(uint256 indexed year, uint256 indexed month, uint256 indexed day, bool isHolidayET);

    function setHolidayET(uint256 _year, uint256 _month, uint256 _day, bool _isHolidayET) external;

    function isHolidayET(bytes32 _holidayKey) external view returns (bool);

}