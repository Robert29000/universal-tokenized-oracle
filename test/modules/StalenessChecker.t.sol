// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IUniversalOracleBase} from "src/interfaces/IUniversalOracleBase.sol";
import {IStalenessChecker} from "src/modules/interfaces/IStalenessChecker.sol";
import {stdError} from "forge-std/StdError.sol";

import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {ETTimestamp} from "src/libraries/ETTimestamp.sol";
import {StalenessCheckerWrapper} from "test/mocks/wrappers/StalenessCheckerWrapper.sol";
import {MockAggregator} from "test/mocks/MockAggregator.sol";
import {TimeFixtures as T} from "test/utils/TimeFixtures.sol";

contract StalenessCheckerTest is Test {
    MockAggregator internal feed;
    StalenessCheckerWrapper internal oracle;

    uint256 internal constant MAX = 4 days;
    uint256 internal constant TRADING = 1 hours;
    uint256 internal constant REOPEN = 30 minutes;

    uint256 internal constant FRIDAY_CLOSE = 4 days + 20 hours;
    uint256 internal constant SUNDAY_REOPEN = 6 days + 20 hours;
    uint256 internal constant WEEK = 7 days;

    /// @dev 1970-01-05 00:00 is a Monday. Used as a synthetic "ET" week origin for _checkETWeekendTrading.
    uint256 internal constant SYNTHETIC_MONDAY = 4 days;

    // Wednesday 12:00 ET of the reference weeks
    uint256 internal constant EDT_WED_NOON = T.EDT_MON_0000 + 2 days + 12 hours;
    uint256 internal constant EST_WED_NOON = T.EST_MON_0000 + 2 days + 12 hours;

    function setUp() public {
        vm.warp(EDT_WED_NOON);
        feed = new MockAggregator(8, "MSFT / USD");
        feed.setAnswer(400e8, block.timestamp);
        oracle = new StalenessCheckerWrapper(address(feed), MAX, TRADING, REOPEN);
    }

    /// @dev startedAt is deliberately set to 0 (never equal to updatedAt): the module must only look at
    ///      updatedAt. With startedAt == updatedAt a mutant reading startedAt would be indistinguishable.
    function _round(int256 _answer, uint256 _updatedAt) internal pure returns (IUniversalOracleBase.RoundData memory) {
        return IUniversalOracleBase.RoundData(1, _answer, 0, _updatedAt, 1);
    }

    function _expectOk(uint256 _now, uint256 _updatedAt) internal {
        vm.warp(_now);
        oracle.exposed_afterRead(_round(1, _updatedAt));
    }

    function _expectRevert(uint256 _now, uint256 _updatedAt, bytes4 _selector) internal {
        vm.warp(_now);
        vm.expectRevert(abi.encodeWithSelector(_selector));
        oracle.exposed_afterRead(_round(1, _updatedAt));
    }

    // ================================================================== constructor

    function test_constructor_SetsImmutables() public view {
        assertEq(oracle.maxStaleness(), MAX);
        assertEq(oracle.tradingStaleness(), TRADING);
        assertEq(oracle.reopenTimeWait(), REOPEN);
        assertEq(address(oracle.aggregator()), address(feed));
    }

    function test_constructor_BoundaryValuesAccepted() public {
        // maxStaleness == tradingStaleness, reopenTimeWait == tradingStaleness
        StalenessCheckerWrapper o = new StalenessCheckerWrapper(address(feed), 1, 1, 1);
        assertEq(o.maxStaleness(), 1);
        assertEq(o.reopenTimeWait(), 1);
        // reopenTimeWait == 0
        o = new StalenessCheckerWrapper(address(feed), type(uint256).max, type(uint256).max, 0);
        assertEq(o.reopenTimeWait(), 0);
    }

    function test_RevertWhen_constructor_MaxStalenessZero() public {
        vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.MaxStalenessZero.selector));
        new StalenessCheckerWrapper(address(feed), 0, 0, 0);
    }

    function test_RevertWhen_constructor_TradingStalenessZero() public {
        vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.TradingStalenessZero.selector));
        new StalenessCheckerWrapper(address(feed), 1, 0, 0);
    }

    function test_RevertWhen_constructor_MaxStalenessLessThanTradingStaleness() public {
        vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.MaxStalenessLessThanTradingStaleness.selector));
        new StalenessCheckerWrapper(address(feed), 1 hours - 1, 1 hours, 0);
    }

    function test_RevertWhen_constructor_ReopenTimeWaitGreaterThanTradingStaleness() public {
        vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.ReopenTimeWaitGreaterThanTradingStaleness.selector));
        new StalenessCheckerWrapper(address(feed), 2 hours, 1 hours, 1 hours + 1);
    }

    function test_RevertWhen_constructor_AggregatorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.AggregatorZeroAddress.selector));
        new StalenessCheckerWrapper(address(0), MAX, TRADING, REOPEN);
    }

    function testFuzz_constructor(uint256 _max, uint256 _trading, uint256 _reopen) public {
        bytes4 err;
        if (_max == 0) err = IStalenessChecker.MaxStalenessZero.selector;
        else if (_trading == 0) err = IStalenessChecker.TradingStalenessZero.selector;
        else if (_max < _trading) err = IStalenessChecker.MaxStalenessLessThanTradingStaleness.selector;
        else if (_reopen > _trading) err = IStalenessChecker.ReopenTimeWaitGreaterThanTradingStaleness.selector;

        if (err != bytes4(0)) vm.expectRevert(abi.encodeWithSelector(err));
        StalenessCheckerWrapper o = new StalenessCheckerWrapper(address(feed), _max, _trading, _reopen);
        if (err == bytes4(0)) {
            assertEq(o.maxStaleness(), _max);
            assertEq(o.tradingStaleness(), _trading);
            assertEq(o.reopenTimeWait(), _reopen);
        }
    }

    // ================================================================== _afterRead: base + max staleness

    function test_RevertWhen_afterRead_PriceZeroCheckedBeforeStaleness() public {
        vm.warp(EDT_WED_NOON);
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.PriceZero.selector));
        oracle.exposed_afterRead(_round(0, 0)); // also maximally stale
    }

    function test_afterRead_MaxStalenessBoundary() public {
        // trading == max so the trading branch is never entered inside the max window.
        oracle = new StalenessCheckerWrapper(address(feed), 1 days, 1 days, 0);
        _expectOk(EDT_WED_NOON, EDT_WED_NOON - 1 days);
        _expectRevert(EDT_WED_NOON, EDT_WED_NOON - 1 days - 1, IStalenessChecker.MaxStalenessReached.selector);
    }

    function test_RevertWhen_afterRead_MaxStalenessTakesPrecedenceOverTrading() public {
        _expectRevert(EDT_WED_NOON, EDT_WED_NOON - MAX - 1, IStalenessChecker.MaxStalenessReached.selector);
    }

    function test_RevertWhen_afterRead_MaxStalenessOnWeekend() public {
        // Saturday: even a weekend read fails once maxStaleness has elapsed.
        uint256 sat = T.EDT_FRI_2000 + 16 hours;
        _expectRevert(sat, sat - MAX - 1, IStalenessChecker.MaxStalenessReached.selector);
    }

    function test_afterRead_UpdatedAtInFuture() public {
        _expectOk(EDT_WED_NOON, EDT_WED_NOON + 1 days);
    }

    // ================================================================== _afterRead: trading hours

    function test_afterRead_TradingStalenessBoundaryEDT() public {
        _expectOk(EDT_WED_NOON, EDT_WED_NOON);
        _expectOk(EDT_WED_NOON, EDT_WED_NOON - TRADING);
        _expectRevert(EDT_WED_NOON, EDT_WED_NOON - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_TradingStalenessBoundaryEST() public {
        _expectOk(EST_WED_NOON, EST_WED_NOON - TRADING);
        _expectRevert(EST_WED_NOON, EST_WED_NOON - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_RevertWhen_afterRead_StaleJustBeforeFridayClose() public {
        uint256 t = T.EDT_FRI_2000 - 1;
        _expectRevert(t, t - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_RevertWhen_afterRead_StaleMondayMorning() public {
        // Mon 00:00 ET is 4h after reopen, past the 30 min grace period.
        uint256 t = T.EDT_NEXT_MON_0000;
        _expectRevert(t, T.EDT_FRI_2000, IStalenessChecker.TradingStalenessReached.selector);
    }

    // ================================================================== _afterRead: weekend

    function test_afterRead_WeekendLastUpdateAtTradingStalenessBeforeClose() public {
        uint256 sat = T.EDT_FRI_2000 + 16 hours;
        _expectOk(sat, T.EDT_FRI_2000 - TRADING); // updatedAt + trading == close
        _expectRevert(sat, T.EDT_FRI_2000 - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_WeekendEST() public {
        uint256 sat = T.EST_FRI_2000 + 16 hours;
        _expectOk(sat, T.EST_FRI_2000 - TRADING);
        _expectRevert(sat, T.EST_FRI_2000 - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_ExactlyAtFridayClose() public {
        // At close, a feed exactly TRADING old is still fresh; one second older is stale (close == now).
        _expectOk(T.EDT_FRI_2000, T.EDT_FRI_2000 - TRADING);
        _expectRevert(T.EDT_FRI_2000, T.EDT_FRI_2000 - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_SundayJustBeforeReopen() public {
        _expectOk(T.EDT_SUN_2000 - 1, T.EDT_FRI_2000 - 10 minutes);
    }

    function test_afterRead_GracePeriodAfterReopen() public {
        uint256 updated = T.EDT_FRI_2000 - 10 minutes;
        _expectOk(T.EDT_SUN_2000, updated);
        _expectOk(T.EDT_SUN_2000 + REOPEN - 1, updated);
        _expectRevert(T.EDT_SUN_2000 + REOPEN, updated, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_GracePeriodAfterReopenEST() public {
        uint256 updated = T.EST_FRI_2000 - 10 minutes;
        _expectOk(T.EST_SUN_2000 + REOPEN - 1, updated);
        _expectRevert(T.EST_SUN_2000 + REOPEN, updated, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_FreshUpdateDuringGraceIsAccepted() public {
        _expectOk(T.EDT_SUN_2000 + 10 minutes, T.EDT_SUN_2000 + 5 minutes);
    }

    function test_afterRead_SpringForwardWeekend() public {
        // Fri 2024-03-08 20:00 EST (Sat 01:00 UTC) close, Sunday 2024-03-10 is the switch to EDT.
        uint256 close = 1709946000;
        uint256 sundayNoonEDT = T.DST_START_2024 + 9 hours; // Sun 12:00 EDT
        _expectOk(sundayNoonEDT, close - TRADING);
        _expectRevert(sundayNoonEDT, close - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_FallBackWeekend() public {
        // Fri 2024-11-01 20:00 EDT (Sat 00:00 UTC) close, Sunday 2024-11-03 is the switch to EST.
        uint256 close = 1730505600;
        uint256 sundayNoonEST = T.DST_END_2024 + 11 hours; // Sun 12:00 EST
        _expectOk(sundayNoonEST, close - TRADING);
        _expectRevert(sundayNoonEST, close - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_NewYearWeekend() public {
        // Sat 2022-01-01 12:00 ET; close was Fri 2021-12-31 20:00 EST (2022-01-01 01:00 UTC).
        uint256 close = 1640998800;
        uint256 satNoon = close + 16 hours;
        _expectOk(satNoon, close - TRADING);
        _expectRevert(satNoon, close - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_RevertWhen_afterRead_YearBeyond9999() public {
        // The DST lookup is only reached when the trading staleness window has elapsed.
        uint256 t = T.MAX_DATETIME + 1;
        _expectOk(t, t - TRADING); // no DST lookup
        _expectRevert(t, t - TRADING - 1, UnixTimestamp.InvalidYear.selector);
    }

    // ================================================================== end-to-end through _price

    function test_price_ReturnsAnswerWhenFresh() public view {
        assertEq(oracle.exposed_price(), 400e8);
    }

    function test_RevertWhen_price_TradingStale() public {
        vm.warp(EDT_WED_NOON + TRADING + 1);
        vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.TradingStalenessReached.selector));
        oracle.exposed_price();
    }

    // ================================================================== _getDSTBoundaries

    function test_getDSTBoundaries_UsesUTCYear() public view {
        (uint256 s, uint256 e) = oracle.exposed_getDSTBoundaries(EDT_WED_NOON);
        assertEq(s, T.DST_START_2024);
        assertEq(e, T.DST_END_2024);
        (s, e) = oracle.exposed_getDSTBoundaries(T.JAN_01_2024 - 1); // 2023-12-31 23:59:59 UTC
        assertEq(s, 1678604400); // 2023-03-12 07:00 UTC
        assertEq(e, 1699164000); // 2023-11-05 06:00 UTC
    }

    function test_RevertWhen_getDSTBoundaries_YearBeyond9999() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        oracle.exposed_getDSTBoundaries(T.MAX_DATETIME + 1);
    }

    // ================================================================== _isETWeekendTrading (no grace)

    function test_isETWeekendTrading_EDTWeek() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertFalse(oracle.exposed_isETWeekendTrading(T.EDT_MON_0000, s, e, 0), "Mon 00:00");
        assertFalse(oracle.exposed_isETWeekendTrading(T.EDT_FRI_2000 - 1, s, e, 0), "Fri 19:59:59");
        assertTrue(oracle.exposed_isETWeekendTrading(T.EDT_FRI_2000, s, e, 0), "Fri 20:00");
        assertTrue(oracle.exposed_isETWeekendTrading(T.EDT_SUN_2000 - 1, s, e, 0), "Sun 19:59:59");
        assertFalse(oracle.exposed_isETWeekendTrading(T.EDT_SUN_2000, s, e, 0), "Sun 20:00");
        assertFalse(oracle.exposed_isETWeekendTrading(T.EDT_NEXT_MON_0000 - 1, s, e, 0), "Sun 23:59:59");
        assertFalse(oracle.exposed_isETWeekendTrading(T.EDT_NEXT_MON_0000, s, e, 0), "next Mon 00:00");
    }

    function test_isETWeekendTrading_ESTWeek() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertFalse(oracle.exposed_isETWeekendTrading(T.EST_FRI_2000 - 1, s, e, 0), "Fri 19:59:59");
        assertTrue(oracle.exposed_isETWeekendTrading(T.EST_FRI_2000, s, e, 0), "Fri 20:00");
        assertTrue(oracle.exposed_isETWeekendTrading(T.EST_SUN_2000 - 1, s, e, 0), "Sun 19:59:59");
        assertFalse(oracle.exposed_isETWeekendTrading(T.EST_SUN_2000, s, e, 0), "Sun 20:00");
    }

    // ================================================================== _isETWeekendTrading (grace)

    function test_isETWeekendTradingWithGrace_SundayReopen() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 grace = 30 minutes;
        assertTrue(oracle.exposed_isETWeekendTrading(T.EDT_SUN_2000, s, e, grace), "reopen");
        assertTrue(oracle.exposed_isETWeekendTrading(T.EDT_SUN_2000 + grace - 1, s, e, grace), "grace - 1");
        assertFalse(oracle.exposed_isETWeekendTrading(T.EDT_SUN_2000 + grace, s, e, grace), "grace");
    }

    function test_isETWeekendTradingWithGrace_GraceSpillsIntoMonday() public view {
        // A grace period longer than 4h (Sun 20:00 -> Mon 00:00) continues in the Mon-Fri branch.
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 grace = 5 hours;
        assertTrue(oracle.exposed_isETWeekendTrading(T.EDT_NEXT_MON_0000 - 1, s, e, grace), "Sun 23:59:59");
        assertTrue(oracle.exposed_isETWeekendTrading(T.EDT_NEXT_MON_0000, s, e, grace), "Mon 00:00");
        assertTrue(oracle.exposed_isETWeekendTrading(T.EDT_NEXT_MON_0000 + 1 hours - 1, s, e, grace), "Mon 00:59:59");
        assertFalse(oracle.exposed_isETWeekendTrading(T.EDT_NEXT_MON_0000 + 1 hours, s, e, grace), "Mon 01:00");
    }

    function test_isETWeekendTradingWithGrace_ESTWeek() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 grace = 1 hours;
        assertTrue(oracle.exposed_isETWeekendTrading(T.EST_SUN_2000 + grace - 1, s, e, grace));
        assertFalse(oracle.exposed_isETWeekendTrading(T.EST_SUN_2000 + grace, s, e, grace));
    }

    // ================================================================== _checkETWeekendTrading

    function test_checkETWeekendTrading_Branches() public view {
        uint256 m = SYNTHETIC_MONDAY;
        // Branch 1: Mon 00:00 .. Fri 19:59:59, no grace
        assertFalse(oracle.exposed_checkETWeekendTrading(m, 0), "Mon 00:00");
        assertFalse(oracle.exposed_checkETWeekendTrading(m + FRIDAY_CLOSE - 1, 0), "Fri 19:59:59");
        // Branch 2: Fri 20:00 .. Sun 19:59:59
        assertTrue(oracle.exposed_checkETWeekendTrading(m + FRIDAY_CLOSE, 0), "Fri 20:00");
        assertTrue(oracle.exposed_checkETWeekendTrading(m + SUNDAY_REOPEN - 1, 0), "Sun 19:59:59");
        // Branch 3: Sun 20:00 .. Sun 23:59:59
        assertFalse(oracle.exposed_checkETWeekendTrading(m + SUNDAY_REOPEN, 0), "Sun 20:00");
        assertFalse(oracle.exposed_checkETWeekendTrading(m + WEEK - 1, 0), "Sun 23:59:59");
    }

    function test_checkETWeekendTrading_GraceInSundayBranch() public view {
        uint256 m = SYNTHETIC_MONDAY;
        assertTrue(oracle.exposed_checkETWeekendTrading(m + SUNDAY_REOPEN, 1), "sinceReopen 0 < 1");
        assertFalse(oracle.exposed_checkETWeekendTrading(m + SUNDAY_REOPEN + 1, 1), "sinceReopen 1 < 1");
        assertTrue(oracle.exposed_checkETWeekendTrading(m + WEEK - 1, 4 hours), "Sun 23:59:59, grace 4h");
    }

    function test_checkETWeekendTrading_GraceInWeekdayBranch() public view {
        uint256 m = SYNTHETIC_MONDAY;
        // Mon 00:00 is 4h after Sun 20:00
        assertFalse(oracle.exposed_checkETWeekendTrading(m, 4 hours), "Mon 00:00, grace 4h");
        assertTrue(oracle.exposed_checkETWeekendTrading(m, 4 hours + 1), "Mon 00:00, grace 4h+1");
        // A grace covering the whole working week keeps the market "closed" until Fri 20:00.
        assertTrue(oracle.exposed_checkETWeekendTrading(m + FRIDAY_CLOSE - 1, FRIDAY_CLOSE + 4 hours), "Fri 19:59:59");
        assertFalse(oracle.exposed_checkETWeekendTrading(m + FRIDAY_CLOSE - 1, FRIDAY_CLOSE + 4 hours - 1), "Fri 19:59:59 b");
    }

    function test_checkETWeekendTrading_MaxGrace() public view {
        uint256 m = SYNTHETIC_MONDAY;
        assertTrue(oracle.exposed_checkETWeekendTrading(m, type(uint256).max));
        assertTrue(oracle.exposed_checkETWeekendTrading(m + SUNDAY_REOPEN, type(uint256).max));
    }

    /// @dev Reference model: closed in [Fri 20:00, Sun 20:00) and during `grace` seconds after Sun 20:00.
    function testFuzz_checkETWeekendTrading_MatchesModel(uint256 _et, uint256 _grace) public view {
        _et = bound(_et, 0, type(uint128).max);
        _grace = bound(_grace, 0, 2 * WEEK);
        uint256 intoWeek = ((_et / 1 days + 3) % 7) * 1 days + (_et % 1 days);
        uint256 sinceReopen = (intoWeek + WEEK - SUNDAY_REOPEN) % WEEK;
        bool closed = intoWeek >= FRIDAY_CLOSE && intoWeek < SUNDAY_REOPEN;
        bool expected = closed || sinceReopen < _grace;
        assertEq(oracle.exposed_checkETWeekendTrading(_et, _grace), expected);
    }

    // ================================================================== _getLastETFridayCloseTimestampInUTC

    function test_getLastETFridayCloseTimestampInUTC_ExactlyAtCloseEDT() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(T.EDT_FRI_2000, s, e), T.EDT_FRI_2000);
    }

    function test_getLastETFridayCloseTimestampInUTC_OneSecondBeforeCloseEDT() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(T.EDT_FRI_2000 - 1, s, e), T.EDT_FRI_2000 - WEEK);
    }

    function test_getLastETFridayCloseTimestampInUTC_ExactlyAtCloseEST() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(T.EST_FRI_2000, s, e), T.EST_FRI_2000);
    }

    function test_getLastETFridayCloseTimestampInUTC_SaturdayUTCBeforeCloseEST() public view {
        // Sat 00:30 UTC == Fri 19:30 EST: same UTC Saturday, but close (01:00 UTC) is still in the future,
        // so the `closeUTC > _timestamp` branch must step back one week.
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(T.EST_FRI_2000 - 30 minutes, s, e), T.EST_FRI_2000 - WEEK);
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(T.EST_FRI_2000 - 1, s, e), T.EST_FRI_2000 - WEEK);
    }

    function test_getLastETFridayCloseTimestampInUTC_MidWeekAndWeekend() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        // Wednesday -> previous Friday
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(T.EDT_MON_0000 + 2 days + 12 hours, s, e), T.EDT_FRI_2000 - WEEK);
        // Saturday noon, Sunday 21:00 ET (Monday UTC), Monday 00:00 ET -> this Friday
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(T.EDT_FRI_2000 + 16 hours, s, e), T.EDT_FRI_2000);
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(T.EDT_SUN_2000 + 1 hours, s, e), T.EDT_FRI_2000);
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(T.EDT_NEXT_MON_0000, s, e), T.EDT_FRI_2000);
        // Friday 23:59:59 UTC (Friday afternoon ET) -> previous Friday
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(T.EDT_FRI_2000 - 1, s, e), T.EDT_FRI_2000 - WEEK);
    }

    function test_getLastETFridayCloseTimestampInUTC_SpringForwardWeekend() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 friCloseEST = 1709946000; // Fri 2024-03-08 20:00 EST == Sat 2024-03-09 01:00 UTC
        uint256 nextFriCloseEDT = 1710547200; // Fri 2024-03-15 20:00 EDT == Sat 2024-03-16 00:00 UTC
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(s + 5 hours, s, e), friCloseEST, "Sunday after switch");
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(nextFriCloseEDT - 1, s, e), friCloseEST, "Fri before next close");
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(nextFriCloseEDT, s, e), nextFriCloseEDT, "next close");
    }

    function test_getLastETFridayCloseTimestampInUTC_FallBackWeekend() public view {
        (uint256 s, uint256 e) = (T.DST_START_2024, T.DST_END_2024);
        uint256 friCloseEDT = 1730505600; // Fri 2024-11-01 20:00 EDT == Sat 2024-11-02 00:00 UTC
        uint256 nextFriCloseEST = 1731114000; // Fri 2024-11-08 20:00 EST == Sat 2024-11-09 01:00 UTC
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(e + 6 hours, s, e), friCloseEDT, "Sunday after switch");
        // Sat 00:30 UTC (still Fri in EST) -> step back one week, into the EDT regime
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(nextFriCloseEST - 30 minutes, s, e), friCloseEDT, "step back");
        assertEq(oracle.exposed_getLastETFridayCloseTimestampInUTC(nextFriCloseEST, s, e), nextFriCloseEST, "next close");
    }

    function test_RevertWhen_getLastETFridayCloseTimestampInUTC_BeforeFirstSaturday() public {
        // 1970-01-01 is a Thursday: there is no Saturday at or before it -> arithmetic underflow.
        vm.expectRevert(stdError.arithmeticError);
        oracle.exposed_getLastETFridayCloseTimestampInUTC(0, 0, 0);
    }

    function testFuzz_getLastETFridayCloseTimestampInUTC_IsMostRecentFridayClose(uint256 _ts) public view {
        _ts = bound(_ts, T.JAN_01_2024, 4102444800); // 2024-01-01 .. 2100-01-01
        (uint256 year,,) = UnixTimestamp.getDate(_ts);
        (uint256 s, uint256 e) = ETTimestamp.getETTransitionBoundariesInUTC(year);

        uint256 close = oracle.exposed_getLastETFridayCloseTimestampInUTC(_ts, s, e);
        assertLe(close, _ts, "close in the future");
        assertLt(_ts - close, WEEK + 1 hours, "close older than a week");

        // The close is a Friday 20:00 in ET.
        uint256 closeET = ETTimestamp.toETTimestamp(close, s, e);
        assertEq(UnixTimestamp.getWeekday(closeET), 4, "not a Friday in ET");
        assertEq(closeET % 1 days, 20 hours, "not 20:00 ET");

        // No later Friday close exists in (close, _ts].
        uint256 nextClose = oracle.exposed_getLastETFridayCloseTimestampInUTC(close + WEEK + 1 hours, s, e);
        assertGt(nextClose, _ts, "a later close was skipped");
    }

    // ================================================================== fuzz

    /// @dev Mon 00:30 .. Fri 19:59:59 ET: reverts iff older than tradingStaleness (or maxStaleness).
    function testFuzz_afterRead_TradingHours(uint256 _now, uint256 _age) public {
        _now = bound(_now, T.EDT_MON_0000 + REOPEN, T.EDT_FRI_2000 - 1);
        _age = bound(_age, 0, MAX + 1 hours);
        vm.warp(_now);
        if (_age > MAX) {
            vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.MaxStalenessReached.selector));
        } else if (_age > TRADING) {
            vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.TradingStalenessReached.selector));
        }
        oracle.exposed_afterRead(_round(1, _now - _age));
    }

    /// @dev Fri 20:00 .. Sun 20:00 + grace ET: reverts iff the last update was older than
    ///      tradingStaleness at the Friday close (or maxStaleness overall).
    function testFuzz_afterRead_Weekend(uint256 _now, uint256 _age, bool _est) public {
        (uint256 close, uint256 reopen) = _est ? (T.EST_FRI_2000, T.EST_SUN_2000) : (T.EDT_FRI_2000, T.EDT_SUN_2000);
        _now = bound(_now, close, reopen + REOPEN - 1);
        _age = bound(_age, 0, MAX + 1 hours);
        uint256 updatedAt = _now - _age;
        vm.warp(_now);
        if (_age > MAX) {
            vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.MaxStalenessReached.selector));
        } else if (_age > TRADING && updatedAt + TRADING < close) {
            vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.TradingStalenessReached.selector));
        }
        oracle.exposed_afterRead(_round(1, updatedAt));
    }

    // ================================================================== updatedAt vs startedAt

    function test_afterRead_UsesUpdatedAtNotStartedAt() public {
        vm.warp(EDT_WED_NOON);
        // Old round start, fresh update: accepted.
        oracle.exposed_afterRead(IUniversalOracleBase.RoundData(1, 1, EDT_WED_NOON - 10 days, EDT_WED_NOON, 1));
        // Fresh round start, stale update: rejected on updatedAt.
        vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.TradingStalenessReached.selector));
        oracle.exposed_afterRead(
            IUniversalOracleBase.RoundData(1, 1, EDT_WED_NOON, EDT_WED_NOON - TRADING - 1, 1)
        );
        vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.MaxStalenessReached.selector));
        oracle.exposed_afterRead(IUniversalOracleBase.RoundData(1, 1, EDT_WED_NOON, EDT_WED_NOON - MAX - 1, 1));
    }

    function test_price_UsesFeedUpdatedAtNotStartedAt() public {
        // End-to-end: each latestRoundData field must land in the right RoundData slot.
        feed.setRoundData(7, 400e8, EDT_WED_NOON - 10 days, EDT_WED_NOON, 7);
        assertEq(oracle.exposed_price(), 400e8);
        feed.setRoundData(8, 400e8, EDT_WED_NOON, EDT_WED_NOON - TRADING - 1, 8);
        vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.TradingStalenessReached.selector));
        oracle.exposed_price();
    }

    // ================================================================== malformed feed data

    function test_RevertWhen_afterRead_UpdatedAtOverflows() public {
        // A feed reporting updatedAt near uint256 max makes `updatedAt + maxStaleness` overflow (fails closed).
        vm.expectRevert(stdError.arithmeticError);
        oracle.exposed_afterRead(_round(1, type(uint256).max));
    }

    function test_afterRead_UpdatedAtZeroIsMaxStale() public {
        _expectRevert(EDT_WED_NOON, 0, IStalenessChecker.MaxStalenessReached.selector);
    }

    function test_RevertWhen_afterRead_FreshAtPreviousWeeksCloseOnly() public {
        // Isolate the trading rule with a large maxStaleness: on Saturday, a price that was fresh at LAST
        // week's close (but not at this week's close) must be rejected.
        StalenessCheckerWrapper o = new StalenessCheckerWrapper(address(feed), 30 days, TRADING, REOPEN);
        vm.warp(T.EDT_FRI_2000 + 16 hours);
        vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.TradingStalenessReached.selector));
        o.exposed_afterRead(_round(1, T.EDT_FRI_2000 - 1 weeks));
    }

    // ================================================================== DST / new-year weekend reopen

    function _assertReopenWindow(uint256 _close, uint256 _reopen) internal {
        uint256 updated = _close - 10 minutes;
        _expectOk(_reopen - 1, updated);
        _expectOk(_reopen, updated);
        _expectOk(_reopen + REOPEN - 1, updated);
        _expectRevert(_reopen + REOPEN, updated, IStalenessChecker.TradingStalenessReached.selector);
        // Just before the close the market is open: a 10-minute-old price is fine, a stale one is not.
        _expectOk(_close - 1, _close - 1 - TRADING);
        _expectRevert(_close - 1, _close - 2 - TRADING, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_SpringForwardWeekendReopen() public {
        // Close Fri 2024-03-08 20:00 EST, reopen Sun 2024-03-10 20:00 EDT (= Mon 00:00 UTC).
        _assertReopenWindow(1709946000, 1710115200);
    }

    function test_afterRead_FallBackWeekendReopen() public {
        // Close Fri 2024-11-01 20:00 EDT, reopen Sun 2024-11-03 20:00 EST (= Mon 01:00 UTC).
        _assertReopenWindow(1730505600, 1730682000);
    }

    function test_afterRead_NewYearWeekendReopen() public {
        // Close Fri 2021-12-31 20:00 EST (UTC year 2022), reopen Sun 2022-01-02 20:00 EST.
        _assertReopenWindow(1640998800, 1641171600);
    }

    // ================================================================== fuzz: any week 2007..2099

    /// @dev Model of the staleness rule for any timestamp, built on the ETTimestamp library and the module's
    ///      weekend helpers (both checked separately against Python zoneinfo in test/differential/). Covers
    ///      every week, including the DST and New Year weekends, rather than one fixed EDT/EST week.
    function testFuzz_afterRead_AnyWeek(uint256 _now, uint256 _age) public {
        _now = bound(_now, 1168214400, 4102444799); // 2007-01-08 .. 2099-12-31
        _age = bound(_age, 0, MAX + 1 hours);
        uint256 updatedAt = _now - _age;
        (uint256 year,,) = UnixTimestamp.getDate(_now);
        (uint256 s, uint256 e) = ETTimestamp.getETTransitionBoundariesInUTC(year);
        bool closedOrGrace = oracle.exposed_isETWeekendTrading(_now, s, e, REOPEN);
        uint256 close = oracle.exposed_getLastETFridayCloseTimestampInUTC(_now, s, e);

        vm.warp(_now);
        if (_age > MAX) {
            vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.MaxStalenessReached.selector));
        } else if (_age > TRADING && (!closedOrGrace || updatedAt + TRADING < close)) {
            vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.TradingStalenessReached.selector));
        }
        oracle.exposed_afterRead(_round(1, updatedAt));
    }
}
