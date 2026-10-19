// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {UnixTimestampWrapper} from "test/mocks/wrappers/UnixTimestampWrapper.sol";
import {TimeFixtures as T} from "test/utils/TimeFixtures.sol";

contract UnixTimestampTest is Test {
    UnixTimestampWrapper internal lib;

    uint256 internal constant DAY = 86400;
    uint256 internal constant MONDAY = 0;
    uint256 internal constant THURSDAY = 3;
    uint256 internal constant FRIDAY = 4;
    uint256 internal constant SATURDAY = 5;
    uint256 internal constant SUNDAY = 6;

    function setUp() public {
        lib = new UnixTimestampWrapper();
    }

    // ------------------------------------------------------------------ helpers

    function _assertDate(uint256 _ts, uint256 _y, uint256 _m, uint256 _d) internal view {
        (uint256 y, uint256 m, uint256 d) = lib.getDate(_ts);
        assertEq(y, _y, "year");
        assertEq(m, _m, "month");
        assertEq(d, _d, "day");
    }

    /// @dev Independent leap-year / month-length model used by the fuzz tests.
    function _isLeap(uint256 _y) internal pure returns (bool) {
        return (_y % 4 == 0 && _y % 100 != 0) || _y % 400 == 0;
    }

    function _daysInMonth(uint256 _y, uint256 _m) internal pure returns (uint256) {
        if (_m == 2) return _isLeap(_y) ? 29 : 28;
        if (_m == 4 || _m == 6 || _m == 9 || _m == 11) return 30;
        return 31;
    }

    // ================================================================== getDate

    function test_getDate_Epoch() public view {
        _assertDate(0, 1970, 1, 1);
    }

    function test_getDate_LastSecondOfFirstDay() public view {
        _assertDate(DAY - 1, 1970, 1, 1);
        _assertDate(DAY, 1970, 1, 2);
    }

    function test_getDate_JanuaryAndFebruaryShiftYear() public view {
        // mp >= 10 branch (Jan/Feb) -> month = mp - 9 and year += 1
        _assertDate(T.JAN_01_2024, 2024, 1, 1);
        _assertDate(T.FEB_29_2024, 2024, 2, 29);
    }

    function test_getDate_MarchToDecemberDoNotShiftYear() public view {
        // mp < 10 branch -> month = mp + 3, year unchanged
        _assertDate(T.MAR_01_2024, 2024, 3, 1);
        _assertDate(T.JAN_01_2024 - 1, 2023, 12, 31);
    }

    function test_getDate_YearBoundary() public view {
        _assertDate(T.JAN_01_2024 - 1, 2023, 12, 31);
        _assertDate(T.JAN_01_2024, 2024, 1, 1);
    }

    function test_getDate_LeapDay2024() public view {
        _assertDate(T.FEB_29_2024 - 1, 2024, 2, 28);
        _assertDate(T.FEB_29_2024, 2024, 2, 29);
        _assertDate(T.FEB_29_2024 + DAY - 1, 2024, 2, 29);
        _assertDate(T.MAR_01_2024, 2024, 3, 1);
    }

    function test_getDate_Year2000IsLeap() public view {
        // divisible by 400 -> leap
        _assertDate(951782400, 2000, 2, 29);
        _assertDate(T.MAR_01_2000, 2000, 3, 1);
    }

    function test_getDate_Year2100IsNotLeap() public view {
        // divisible by 100 but not by 400 -> no Feb 29
        _assertDate(T.FEB_28_2100, 2100, 2, 28);
        _assertDate(T.FEB_28_2100 + DAY, 2100, 3, 1);
        assertEq(T.MAR_01_2100, T.FEB_28_2100 + DAY);
    }

    function test_getDate_Year2400IsLeap() public view {
        _assertDate(13574563200, 2400, 2, 29);
    }

    function test_getDate_MaxDatetime() public view {
        _assertDate(T.DEC_31_9999, 9999, 12, 31);
        _assertDate(T.MAX_DATETIME, 9999, 12, 31);
        _assertDate(T.MAX_DATETIME + 1, 10000, 1, 1);
    }

    function test_getDate_Uint256Max() public view {
        // Reference computed in Python with the 146097-day (400-year) Gregorian period.
        _assertDate(type(uint256).max, 3669305236998687180674831492239425019668248843096144521164705134005822, 2, 19);
    }

    function testFuzz_getDate_RoundTripsThroughGetTimestamp(uint256 _ts) public view {
        _ts = bound(_ts, 0, T.MAX_DATETIME);
        (uint256 y, uint256 m, uint256 d) = lib.getDate(_ts);
        assertEq(lib.getTimestamp(y, m, d), _ts - (_ts % DAY));
    }

    function testFuzz_getDate_ComponentsAreInRange(uint256 _ts) public view {
        (uint256 y, uint256 m, uint256 d) = lib.getDate(_ts);
        assertGe(y, 1970);
        assertGe(m, 1);
        assertLe(m, 12);
        assertGe(d, 1);
        assertLe(d, _daysInMonth(y, m));
    }

    function testFuzz_getDate_NextDayIsSuccessor(uint256 _ts) public view {
        _ts = bound(_ts, 0, T.MAX_DATETIME - DAY);
        (uint256 y, uint256 m, uint256 d) = lib.getDate(_ts);
        (uint256 y2, uint256 m2, uint256 d2) = lib.getDate(_ts + DAY);
        if (d < _daysInMonth(y, m)) {
            assertEq(abi.encode(y2, m2, d2), abi.encode(y, m, d + 1));
        } else if (m < 12) {
            assertEq(abi.encode(y2, m2, d2), abi.encode(y, m + 1, uint256(1)));
        } else {
            assertEq(abi.encode(y2, m2, d2), abi.encode(y + 1, uint256(1), uint256(1)));
        }
    }

    // ================================================================== getTimestamp

    function test_getTimestamp_Epoch() public view {
        assertEq(lib.getTimestamp(1970, 1, 1), 0);
    }

    function test_getTimestamp_KnownDates() public view {
        assertEq(lib.getTimestamp(2024, 1, 1), T.JAN_01_2024); // month <= 2 branch
        assertEq(lib.getTimestamp(2024, 2, 29), T.FEB_29_2024); // month <= 2 branch, leap day
        assertEq(lib.getTimestamp(2024, 3, 1), T.MAR_01_2024); // month > 2 branch
        assertEq(lib.getTimestamp(2000, 3, 1), T.MAR_01_2000);
        assertEq(lib.getTimestamp(2100, 2, 28), T.FEB_28_2100);
        assertEq(lib.getTimestamp(2100, 3, 1), T.MAR_01_2100);
        assertEq(lib.getTimestamp(2400, 2, 29), 13574563200);
    }

    function test_getTimestamp_UpperYearBound() public view {
        assertEq(lib.getTimestamp(9999, 12, 31), T.DEC_31_9999);
    }

    function test_getTimestamp_DayBoundsAccepted() public view {
        assertEq(lib.getTimestamp(2024, 1, 31), T.JAN_01_2024 + 30 * DAY);
        assertEq(lib.getTimestamp(2024, 12, 1), 1733011200);
    }

    function test_RevertWhen_getTimestamp_YearBelow1970() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        lib.getTimestamp(1969, 12, 31);
    }

    function test_RevertWhen_getTimestamp_YearZero() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        lib.getTimestamp(0, 1, 1);
    }

    function test_RevertWhen_getTimestamp_YearAbove9999() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        lib.getTimestamp(10000, 1, 1);
    }

    function test_RevertWhen_getTimestamp_MonthZero() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidMonth.selector));
        lib.getTimestamp(2024, 0, 1);
    }

    function test_RevertWhen_getTimestamp_MonthAbove12() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidMonth.selector));
        lib.getTimestamp(2024, 13, 1);
    }

    function test_RevertWhen_getTimestamp_DayZero() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidDay.selector));
        lib.getTimestamp(2024, 1, 0);
    }

    function test_RevertWhen_getTimestamp_DayAbove31() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidDay.selector));
        lib.getTimestamp(2024, 1, 32);
    }

    function test_RevertWhen_getTimestamp_ValidationOrderYearFirst() public {
        // All three components invalid -> the year check fires first.
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        lib.getTimestamp(0, 0, 0);
        // Year valid, month and day invalid -> month check fires next.
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidMonth.selector));
        lib.getTimestamp(1970, 0, 0);
    }

    function test_RevertWhen_getTimestamp_NonExistentDates() public {
        uint256[3][7] memory cases = [
            [uint256(2023), 2, 29], // not a leap year
            [uint256(2100), 2, 29], // divisible by 100, not by 400
            [uint256(2024), 2, 30],
            [uint256(2023), 2, 31],
            [uint256(2024), 4, 31],
            [uint256(2024), 6, 31],
            [uint256(2024), 11, 31]
        ];
        for (uint256 i = 0; i < cases.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidDay.selector));
            lib.getTimestamp(cases[i][0], cases[i][1], cases[i][2]);
        }
    }

    function test_getTimestamp_LeapDayAccepted() public view {
        assertEq(lib.getTimestamp(2024, 2, 29), lib.getTimestamp(2024, 3, 1) - DAY);
        assertEq(lib.getTimestamp(2000, 2, 29), lib.getTimestamp(2000, 3, 1) - DAY); // divisible by 400
    }

    function test_getTimestamp_LastDayOfEachMonth() public view {
        for (uint256 m = 1; m <= 12; m++) {
            uint256 last = _daysInMonth(2023, m);
            uint256 nextMonthStart = m == 12 ? lib.getTimestamp(2024, 1, 1) : lib.getTimestamp(2023, m + 1, 1);
            assertEq(lib.getTimestamp(2023, m, last), nextMonthStart - DAY);
        }
    }

    function testFuzz_getTimestamp_RoundTripsThroughGetDate(uint256 _y, uint256 _m, uint256 _d) public view {
        _y = bound(_y, 1970, 9999);
        _m = bound(_m, 1, 12);
        _d = bound(_d, 1, _daysInMonth(_y, _m));
        uint256 ts = lib.getTimestamp(_y, _m, _d);
        assertEq(ts % DAY, 0);
        _assertDate(ts, _y, _m, _d);
    }

    function testFuzz_getTimestamp_DayIsLinear(uint256 _y, uint256 _m, uint256 _d) public view {
        _y = bound(_y, 1970, 9999);
        _m = bound(_m, 1, 12);
        _d = bound(_d, 1, _daysInMonth(_y, _m));
        assertEq(lib.getTimestamp(_y, _m, _d), lib.getTimestamp(_y, _m, 1) + (_d - 1) * DAY);
    }

    function testFuzz_RevertWhen_getTimestamp_InvalidYear(uint256 _y) public {
        vm.assume(_y < 1970 || _y > 9999);
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        lib.getTimestamp(_y, 1, 1);
    }

    function testFuzz_RevertWhen_getTimestamp_InvalidMonth(uint256 _m) public {
        vm.assume(_m == 0 || _m > 12);
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidMonth.selector));
        lib.getTimestamp(2024, _m, 1);
    }

    function testFuzz_RevertWhen_getTimestamp_InvalidDay(uint256 _d) public {
        vm.assume(_d == 0 || _d > 31);
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidDay.selector));
        lib.getTimestamp(2024, 1, _d);
    }

    function testFuzz_RevertWhen_getTimestamp_DayAfterMonthEnd(uint256 _y, uint256 _m, uint256 _d) public {
        _y = bound(_y, 1970, 9999);
        _m = bound(_m, 1, 12);
        _d = bound(_d, _daysInMonth(_y, _m) + 1, 32); // 32 keeps the range non-empty for 31-day months
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidDay.selector));
        lib.getTimestamp(_y, _m, _d);
    }

    // ================================================================== getWeekday

    function test_getWeekday_EpochIsThursday() public view {
        assertEq(lib.getWeekday(0), THURSDAY);
        assertEq(lib.getWeekday(DAY - 1), THURSDAY);
    }

    function test_getWeekday_FullWeek() public view {
        // 1970-01-05 is the first Monday after the epoch.
        uint256 monday = 4 * DAY;
        for (uint256 i = 0; i < 7; i++) {
            assertEq(lib.getWeekday(monday + i * DAY), i);
        }
        assertEq(lib.getWeekday(monday + 7 * DAY), MONDAY);
    }

    function test_getWeekday_KnownDates() public view {
        assertEq(lib.getWeekday(T.JAN_01_2024), MONDAY);
        assertEq(lib.getWeekday(T.FEB_29_2024), THURSDAY);
        assertEq(lib.getWeekday(T.DEC_31_9999), FRIDAY);
    }

    function test_getWeekday_Uint256MaxDoesNotOverflow() public view {
        assertEq(lib.getWeekday(type(uint256).max), (type(uint256).max / DAY + 3) % 7);
    }

    function testFuzz_getWeekday_PeriodicWithStepOne(uint256 _ts) public view {
        _ts = bound(_ts, 0, type(uint256).max - 7 * DAY);
        uint256 w = lib.getWeekday(_ts);
        assertLt(w, 7);
        assertEq(lib.getWeekday(_ts + DAY), (w + 1) % 7);
        assertEq(lib.getWeekday(_ts + 7 * DAY), w);
    }

    // ================================================================== isWeekendDay

    function test_isWeekendDay_WeekdaysAreNotWeekend() public view {
        uint256 monday = 4 * DAY;
        for (uint256 i = 0; i < 5; i++) {
            assertFalse(lib.isWeekendDay(monday + i * DAY));
        }
    }

    function test_isWeekendDay_SaturdayAndSunday() public view {
        uint256 saturday = 4 * DAY + 5 * DAY;
        assertTrue(lib.isWeekendDay(saturday));
        assertTrue(lib.isWeekendDay(saturday + DAY));
    }

    function test_isWeekendDay_Boundaries() public view {
        uint256 saturday = 9 * DAY; // 1970-01-10 00:00 UTC
        assertFalse(lib.isWeekendDay(saturday - 1)); // Friday 23:59:59
        assertTrue(lib.isWeekendDay(saturday)); // Saturday 00:00:00
        assertTrue(lib.isWeekendDay(saturday + 2 * DAY - 1)); // Sunday 23:59:59
        assertFalse(lib.isWeekendDay(saturday + 2 * DAY)); // Monday 00:00:00
    }

    function testFuzz_isWeekendDay_MatchesWeekday(uint256 _ts) public view {
        assertEq(lib.isWeekendDay(_ts), lib.getWeekday(_ts) >= SATURDAY);
        assertEq(lib.isWeekendDay(_ts), lib.getWeekday(_ts) == SATURDAY || lib.getWeekday(_ts) == SUNDAY);
    }
}
