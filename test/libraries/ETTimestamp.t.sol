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
    uint256 internal constant FRIDAY_CLOSE = 4 days + 20 hours;
    uint256 internal constant SUNDAY_REOPEN = 6 days + 20 hours;
    uint256 internal constant WEEK = 7 days;

    /// @dev 1970-01-05 00:00 is a Monday. Used as a synthetic "ET" week origin for _checkETWeekendTrading.
    uint256 internal constant SYNTHETIC_MONDAY = 4 days;

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

    // ================================================================== isETWeekendTrading (3 args, no grace)

    function test_isETWeekendTrading_EDTWeek() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertFalse(lib.isETWeekendTrading(T.EDT_MON_0000, s, e), "Mon 00:00");
        assertFalse(lib.isETWeekendTrading(T.EDT_FRI_2000 - 1, s, e), "Fri 19:59:59");
        assertTrue(lib.isETWeekendTrading(T.EDT_FRI_2000, s, e), "Fri 20:00");
        assertTrue(lib.isETWeekendTrading(T.EDT_SUN_2000 - 1, s, e), "Sun 19:59:59");
        assertFalse(lib.isETWeekendTrading(T.EDT_SUN_2000, s, e), "Sun 20:00");
        assertFalse(lib.isETWeekendTrading(T.EDT_NEXT_MON_0000 - 1, s, e), "Sun 23:59:59");
        assertFalse(lib.isETWeekendTrading(T.EDT_NEXT_MON_0000, s, e), "next Mon 00:00");
    }

    function test_isETWeekendTrading_ESTWeek() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertFalse(lib.isETWeekendTrading(T.EST_FRI_2000 - 1, s, e), "Fri 19:59:59");
        assertTrue(lib.isETWeekendTrading(T.EST_FRI_2000, s, e), "Fri 20:00");
        assertTrue(lib.isETWeekendTrading(T.EST_SUN_2000 - 1, s, e), "Sun 19:59:59");
        assertFalse(lib.isETWeekendTrading(T.EST_SUN_2000, s, e), "Sun 20:00");
    }

    function testFuzz_isETWeekendTrading_EqualsZeroGraceOverload(uint256 _ts) public view {
        _ts = bound(_ts, T.JAN_01_2024, T.JAN_01_2024 + 365 days);
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertEq(lib.isETWeekendTrading(_ts, s, e), lib.isETWeekendTradingWithGrace(_ts, s, e, 0));
    }

    // ================================================================== isETWeekendTrading (4 args, grace)

    function test_isETWeekendTradingWithGrace_SundayReopen() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 grace = 30 minutes;
        assertTrue(lib.isETWeekendTradingWithGrace(T.EDT_SUN_2000, s, e, grace), "reopen");
        assertTrue(lib.isETWeekendTradingWithGrace(T.EDT_SUN_2000 + grace - 1, s, e, grace), "grace - 1");
        assertFalse(lib.isETWeekendTradingWithGrace(T.EDT_SUN_2000 + grace, s, e, grace), "grace");
    }

    function test_isETWeekendTradingWithGrace_GraceSpillsIntoMonday() public view {
        // A grace period longer than 4h (Sun 20:00 -> Mon 00:00) continues in the Mon-Fri branch.
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 grace = 5 hours;
        assertTrue(lib.isETWeekendTradingWithGrace(T.EDT_NEXT_MON_0000 - 1, s, e, grace), "Sun 23:59:59");
        assertTrue(lib.isETWeekendTradingWithGrace(T.EDT_NEXT_MON_0000, s, e, grace), "Mon 00:00");
        assertTrue(lib.isETWeekendTradingWithGrace(T.EDT_NEXT_MON_0000 + 1 hours - 1, s, e, grace), "Mon 00:59:59");
        assertFalse(lib.isETWeekendTradingWithGrace(T.EDT_NEXT_MON_0000 + 1 hours, s, e, grace), "Mon 01:00");
    }

    function test_isETWeekendTradingWithGrace_ESTWeek() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 grace = 1 hours;
        assertTrue(lib.isETWeekendTradingWithGrace(T.EST_SUN_2000 + grace - 1, s, e, grace));
        assertFalse(lib.isETWeekendTradingWithGrace(T.EST_SUN_2000 + grace, s, e, grace));
    }

    // ================================================================== _checkETWeekendTrading

    function test_checkETWeekendTrading_Branches() public view {
        uint256 m = SYNTHETIC_MONDAY;
        // Branch 1: Mon 00:00 .. Fri 19:59:59, no grace
        assertFalse(lib.checkETWeekendTrading(m, 0), "Mon 00:00");
        assertFalse(lib.checkETWeekendTrading(m + FRIDAY_CLOSE - 1, 0), "Fri 19:59:59");
        // Branch 2: Fri 20:00 .. Sun 19:59:59
        assertTrue(lib.checkETWeekendTrading(m + FRIDAY_CLOSE, 0), "Fri 20:00");
        assertTrue(lib.checkETWeekendTrading(m + SUNDAY_REOPEN - 1, 0), "Sun 19:59:59");
        // Branch 3: Sun 20:00 .. Sun 23:59:59
        assertFalse(lib.checkETWeekendTrading(m + SUNDAY_REOPEN, 0), "Sun 20:00");
        assertFalse(lib.checkETWeekendTrading(m + WEEK - 1, 0), "Sun 23:59:59");
    }

    function test_checkETWeekendTrading_GraceInSundayBranch() public view {
        uint256 m = SYNTHETIC_MONDAY;
        assertTrue(lib.checkETWeekendTrading(m + SUNDAY_REOPEN, 1), "sinceReopen 0 < 1");
        assertFalse(lib.checkETWeekendTrading(m + SUNDAY_REOPEN + 1, 1), "sinceReopen 1 < 1");
        assertTrue(lib.checkETWeekendTrading(m + WEEK - 1, 4 hours), "Sun 23:59:59, grace 4h");
    }

    function test_checkETWeekendTrading_GraceInWeekdayBranch() public view {
        uint256 m = SYNTHETIC_MONDAY;
        // Mon 00:00 is 4h after Sun 20:00
        assertFalse(lib.checkETWeekendTrading(m, 4 hours), "Mon 00:00, grace 4h");
        assertTrue(lib.checkETWeekendTrading(m, 4 hours + 1), "Mon 00:00, grace 4h+1");
        // A grace covering the whole working week keeps the market "closed" until Fri 20:00.
        assertTrue(lib.checkETWeekendTrading(m + FRIDAY_CLOSE - 1, FRIDAY_CLOSE + 4 hours), "Fri 19:59:59");
        assertFalse(lib.checkETWeekendTrading(m + FRIDAY_CLOSE - 1, FRIDAY_CLOSE + 4 hours - 1), "Fri 19:59:59 b");
    }

    function test_checkETWeekendTrading_MaxGrace() public view {
        uint256 m = SYNTHETIC_MONDAY;
        assertTrue(lib.checkETWeekendTrading(m, type(uint256).max));
        assertTrue(lib.checkETWeekendTrading(m + SUNDAY_REOPEN, type(uint256).max));
    }

    /// @dev Reference model: closed in [Fri 20:00, Sun 20:00) and during `grace` seconds after Sun 20:00.
    function testFuzz_checkETWeekendTrading_MatchesModel(uint256 _et, uint256 _grace) public view {
        _et = bound(_et, 0, type(uint128).max);
        _grace = bound(_grace, 0, 2 * WEEK);
        uint256 intoWeek = ((_et / 1 days + 3) % 7) * 1 days + (_et % 1 days);
        uint256 sinceReopen = (intoWeek + WEEK - SUNDAY_REOPEN) % WEEK;
        bool closed = intoWeek >= FRIDAY_CLOSE && intoWeek < SUNDAY_REOPEN;
        bool expected = closed || sinceReopen < _grace;
        assertEq(lib.checkETWeekendTrading(_et, _grace), expected);
    }

    // ================================================================== getLastETFridayCloseInUTC

    function test_getLastETFridayCloseInUTC_ExactlyAtCloseEDT() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertEq(lib.getLastETFridayCloseInUTC(T.EDT_FRI_2000, s, e), T.EDT_FRI_2000);
    }

    function test_getLastETFridayCloseInUTC_OneSecondBeforeCloseEDT() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertEq(lib.getLastETFridayCloseInUTC(T.EDT_FRI_2000 - 1, s, e), T.EDT_FRI_2000 - WEEK);
    }

    function test_getLastETFridayCloseInUTC_ExactlyAtCloseEST() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertEq(lib.getLastETFridayCloseInUTC(T.EST_FRI_2000, s, e), T.EST_FRI_2000);
    }

    function test_getLastETFridayCloseInUTC_SaturdayUTCBeforeCloseEST() public view {
        // Sat 00:30 UTC == Fri 19:30 EST: same UTC Saturday, but close (01:00 UTC) is still in the future,
        // so the `closeUTC > _timestamp` branch must step back one week.
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertEq(lib.getLastETFridayCloseInUTC(T.EST_FRI_2000 - 30 minutes, s, e), T.EST_FRI_2000 - WEEK);
        assertEq(lib.getLastETFridayCloseInUTC(T.EST_FRI_2000 - 1, s, e), T.EST_FRI_2000 - WEEK);
    }

    function test_getLastETFridayCloseInUTC_MidWeekAndWeekend() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        // Wednesday -> previous Friday
        assertEq(lib.getLastETFridayCloseInUTC(T.EDT_MON_0000 + 2 days + 12 hours, s, e), T.EDT_FRI_2000 - WEEK);
        // Saturday noon, Sunday 21:00 ET (Monday UTC), Monday 00:00 ET -> this Friday
        assertEq(lib.getLastETFridayCloseInUTC(T.EDT_FRI_2000 + 16 hours, s, e), T.EDT_FRI_2000);
        assertEq(lib.getLastETFridayCloseInUTC(T.EDT_SUN_2000 + 1 hours, s, e), T.EDT_FRI_2000);
        assertEq(lib.getLastETFridayCloseInUTC(T.EDT_NEXT_MON_0000, s, e), T.EDT_FRI_2000);
        // Friday 23:59:59 UTC (Friday afternoon ET) -> previous Friday
        assertEq(lib.getLastETFridayCloseInUTC(T.EDT_FRI_2000 - 1, s, e), T.EDT_FRI_2000 - WEEK);
    }

    function test_getLastETFridayCloseInUTC_SpringForwardWeekend() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 friCloseEST = 1709946000; // Fri 2024-03-08 20:00 EST == Sat 2024-03-09 01:00 UTC
        uint256 nextFriCloseEDT = 1710547200; // Fri 2024-03-15 20:00 EDT == Sat 2024-03-16 00:00 UTC
        assertEq(lib.getLastETFridayCloseInUTC(s + 5 hours, s, e), friCloseEST, "Sunday after switch");
        assertEq(lib.getLastETFridayCloseInUTC(nextFriCloseEDT - 1, s, e), friCloseEST, "Fri before next close");
        assertEq(lib.getLastETFridayCloseInUTC(nextFriCloseEDT, s, e), nextFriCloseEDT, "next close");
    }

    function test_getLastETFridayCloseInUTC_FallBackWeekend() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 friCloseEDT = 1730505600; // Fri 2024-11-01 20:00 EDT == Sat 2024-11-02 00:00 UTC
        uint256 nextFriCloseEST = 1731114000; // Fri 2024-11-08 20:00 EST == Sat 2024-11-09 01:00 UTC
        assertEq(lib.getLastETFridayCloseInUTC(e + 6 hours, s, e), friCloseEDT, "Sunday after switch");
        // Sat 00:30 UTC (still Fri in EST) -> step back one week, into the EDT regime
        assertEq(lib.getLastETFridayCloseInUTC(nextFriCloseEST - 30 minutes, s, e), friCloseEDT, "step back");
        assertEq(lib.getLastETFridayCloseInUTC(nextFriCloseEST, s, e), nextFriCloseEST, "next close");
    }

    function test_RevertWhen_getLastETFridayCloseInUTC_BeforeFirstSaturday() public {
        // 1970-01-01 is a Thursday: there is no Saturday at or before it -> arithmetic underflow.
        vm.expectRevert(stdError.arithmeticError);
        lib.getLastETFridayCloseInUTC(0, 0, 0);
    }

    function testFuzz_getLastETFridayCloseInUTC_IsMostRecentFridayClose(uint256 _ts) public view {
        _ts = bound(_ts, T.JAN_01_2024, 4102444800); // 2024-01-01 .. 2100-01-01
        (uint256 year,,) = UnixTimestamp.getDate(_ts);
        (uint256 s, uint256 e) = lib.getETTransitionBoundariesInUTC(year);

        uint256 close = lib.getLastETFridayCloseInUTC(_ts, s, e);
        assertLe(close, _ts, "close in the future");
        assertLt(_ts - close, WEEK + 1 hours, "close older than a week");

        // The close is a Friday 20:00 in ET.
        uint256 closeET = lib.toETTimestamp(close, s, e);
        assertEq(UnixTimestamp.getWeekday(closeET), 4, "not a Friday in ET");
        assertEq(closeET % 1 days, 20 hours, "not 20:00 ET");

        // No later Friday close exists in (close, _ts].
        uint256 nextClose = lib.getLastETFridayCloseInUTC(close + WEEK + 1 hours, s, e);
        assertGt(nextClose, _ts, "a later close was skipped");
    }

    // ================================================================== _adjustedUTCForETOffset

    function test_adjustedUTCForETOffset() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertEq(lib.adjustedUTCForETOffset(s - 1, s, e), s - 1 + 1 hours, "EST adds 1h");
        assertEq(lib.adjustedUTCForETOffset(s, s, e), s, "EDT unchanged");
        assertEq(lib.adjustedUTCForETOffset(e - 1, s, e), e - 1, "EDT unchanged (end - 1)");
        assertEq(lib.adjustedUTCForETOffset(e, s, e), e + 1 hours, "EST adds 1h (end)");
    }
}
