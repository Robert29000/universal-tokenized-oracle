// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";

import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {ETTimestampWrapper} from "test/mocks/wrappers/ETTimestampWrapper.sol";
import {TimeFixtures as T} from "test/utils/TimeFixtures.sol";

contract ETTimestampTest is Test {
    ETTimestampWrapper internal lib;

    uint256 internal constant EST = 5 hours;
    uint256 internal constant EDT = 4 hours;

    function setUp() public {
        lib = new ETTimestampWrapper();
    }

    // ================================================================== getETTransitionBoundariesInUTC

    function test_getETTransitionBoundariesInUTC_MarchFirstIsFriday() public view {
        (uint256 s, uint256 e) = lib.getETTransitionBoundariesInUTC(2024);
        assertEq(s, T.DST_START_2024);
        assertEq(e, T.DST_END_2024);
    }

    function test_getETTransitionBoundariesInUTC_MarchFirstIsSaturday() public view {
        (uint256 s, uint256 e) = lib.getETTransitionBoundariesInUTC(2025);
        assertEq(s, T.DST_START_2025);
        assertEq(e, T.DST_END_2025);
    }

    function test_getETTransitionBoundariesInUTC_MarchFirstIsSunday() public view {
        // Exercises the `weekday == 6` (no adjustment) branch for both March and November.
        (uint256 s, uint256 e) = lib.getETTransitionBoundariesInUTC(2026);
        assertEq(s, T.DST_START_2026);
        assertEq(e, T.DST_END_2026);
    }

    function test_getETTransitionBoundariesInUTC_MarchFirstIsMonday() public view {
        (uint256 s, uint256 e) = lib.getETTransitionBoundariesInUTC(2027);
        assertEq(s, T.DST_START_2027);
        assertEq(e, T.DST_END_2027);
    }

    function test_getETTransitionBoundariesInUTC_Year2100() public view {
        (uint256 s, uint256 e) = lib.getETTransitionBoundariesInUTC(2100);
        assertEq(s, T.DST_START_2100);
        assertEq(e, T.DST_END_2100);
    }

    function test_getETTransitionBoundariesInUTC_ExtremeYears() public view {
        // 1970 (Mar 1 = Sunday) and 9999 must not revert.
        (uint256 s, uint256 e) = lib.getETTransitionBoundariesInUTC(1970);
        assertEq(s, 5727600); // 1970-03-08 07:00 UTC
        assertEq(e, 26287200); // 1970-11-01 06:00 UTC
        (s, e) = lib.getETTransitionBoundariesInUTC(9999);
        assertEq(s, 253377010800); // 9999-03-14 07:00 UTC
        assertEq(e, 253397570400); // 9999-11-07 06:00 UTC
    }

    function test_RevertWhen_getETTransitionBoundariesInUTC_YearBelow1970() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        lib.getETTransitionBoundariesInUTC(1969);
    }

    function test_RevertWhen_getETTransitionBoundariesInUTC_YearAbove9999() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        lib.getETTransitionBoundariesInUTC(10000);
    }

    function testFuzz_getETTransitionBoundariesInUTC_Properties(uint256 _year) public view {
        _year = bound(_year, 1970, 9999);
        (uint256 s, uint256 e) = lib.getETTransitionBoundariesInUTC(_year);

        // Start: Sunday, 07:00 UTC, day 8..14 of March.
        assertEq(UnixTimestamp.getWeekday(s), 6, "start weekday");
        assertEq(s % 1 days, 7 hours, "start hour");
        (uint256 y, uint256 m, uint256 d) = UnixTimestamp.getDate(s);
        assertEq(y, _year);
        assertEq(m, 3);
        assertGe(d, 8);
        assertLe(d, 14);

        // End: Sunday, 06:00 UTC, day 1..7 of November.
        assertEq(UnixTimestamp.getWeekday(e), 6, "end weekday");
        assertEq(e % 1 days, 6 hours, "end hour");
        (y, m, d) = UnixTimestamp.getDate(e);
        assertEq(y, _year);
        assertEq(m, 11);
        assertGe(d, 1);
        assertLe(d, 7);
    }

    // ================================================================== getETOffset

    function test_getETOffset_Boundaries() public view {
        uint256 s = T.DST_START_2024;
        uint256 e = T.DST_END_2024;
        assertEq(lib.getETOffset(s - 1, s, e), EST, "start - 1");
        assertEq(lib.getETOffset(s, s, e), EDT, "start");
        assertEq(lib.getETOffset(e - 1, s, e), EDT, "end - 1");
        assertEq(lib.getETOffset(e, s, e), EST, "end");
        assertEq(lib.getETOffset(0, s, e), EST, "zero");
        assertEq(lib.getETOffset(type(uint256).max, s, e), EST, "max");
    }

    function testFuzz_getETOffset(uint256 _ts, uint256 _s, uint256 _e) public view {
        uint256 expected = (_ts >= _s && _ts < _e) ? EDT : EST;
        assertEq(lib.getETOffset(_ts, _s, _e), expected);
    }

    // ================================================================== toETTimestamp

    function test_toETTimestamp_EST() public view {
        assertEq(lib.toETTimestamp(T.EST_MON_0000, T.DST_START_2024, T.DST_END_2024), T.EST_MON_0000 - EST);
        // Result is Monday 00:00 "wall clock" encoded as a UTC timestamp.
        uint256 et = lib.toETTimestamp(T.EST_MON_0000, T.DST_START_2024, T.DST_END_2024);
        assertEq(et % 1 days, 0);
        assertEq(UnixTimestamp.getWeekday(et), 0);
    }

    function test_toETTimestamp_EDT() public view {
        uint256 et = lib.toETTimestamp(T.EDT_MON_0000, T.DST_START_2024, T.DST_END_2024);
        assertEq(et, T.EDT_MON_0000 - EDT);
        assertEq(et % 1 days, 0);
        assertEq(UnixTimestamp.getWeekday(et), 0);
    }

    function test_toETTimestamp_AcrossSpringForward() public view {
        // 01:59:59 EST -> 03:00:00 EDT
        uint256 s = T.DST_START_2024;
        assertEq(lib.toETTimestamp(s - 1, s, T.DST_END_2024) % 1 days, 2 hours - 1);
        assertEq(lib.toETTimestamp(s, s, T.DST_END_2024) % 1 days, 3 hours);
    }

    function test_toETTimestamp_AcrossFallBack() public view {
        // 01:59:59 EDT -> 01:00:00 EST
        uint256 e = T.DST_END_2024;
        assertEq(lib.toETTimestamp(e - 1, T.DST_START_2024, e) % 1 days, 2 hours - 1);
        assertEq(lib.toETTimestamp(e, T.DST_START_2024, e) % 1 days, 1 hours);
    }

    function test_RevertWhen_toETTimestamp_TimestampBelowOffset() public {
        // Underflow guard (only reachable for timestamps in the first hours of 1970).
        vm.expectRevert(stdError.arithmeticError);
        lib.toETTimestamp(EST - 1, T.DST_START_2024, T.DST_END_2024);
    }

    // ================================================================== isETWeekend

    function test_isETWeekend_EDTWeek() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 sat = T.EDT_MON_0000 + 5 days;
        assertFalse(lib.isETWeekend(T.EDT_MON_0000, s, e), "Mon 00:00");
        assertFalse(lib.isETWeekend(T.EDT_FRI_2000, s, e), "Fri 20:00 ET is Sat 00:00 UTC but still Friday in ET");
        assertFalse(lib.isETWeekend(sat - 1, s, e), "Fri 23:59:59");
        assertTrue(lib.isETWeekend(sat, s, e), "Sat 00:00");
        assertTrue(lib.isETWeekend(T.EDT_NEXT_MON_0000 - 1, s, e), "Sun 23:59:59");
        assertFalse(lib.isETWeekend(T.EDT_NEXT_MON_0000, s, e), "next Mon 00:00");
    }

    function test_isETWeekend_ESTWeek() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 sat = T.EST_MON_0000 + 5 days;
        assertFalse(lib.isETWeekend(sat - 1, s, e), "Fri 23:59:59");
        assertTrue(lib.isETWeekend(sat, s, e), "Sat 00:00");
        assertTrue(lib.isETWeekend(T.EST_NEXT_MON_0000 - 1, s, e), "Sun 23:59:59");
        assertFalse(lib.isETWeekend(T.EST_NEXT_MON_0000, s, e), "next Mon 00:00");
    }

    // ================================================================== adjustedUTCForETOffset

    function test_adjustedUTCForETOffset() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertEq(lib.adjustedUTCForETOffset(s - 1, s, e), s - 1 + 1 hours, "EST adds 1h");
        assertEq(lib.adjustedUTCForETOffset(s, s, e), s, "EDT unchanged");
        assertEq(lib.adjustedUTCForETOffset(e - 1, s, e), e - 1, "EDT unchanged (end - 1)");
        assertEq(lib.adjustedUTCForETOffset(e, s, e), e + 1 hours, "EST adds 1h (end)");
    }
}
