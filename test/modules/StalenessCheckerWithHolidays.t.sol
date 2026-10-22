// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IUniversalOracleBase} from "src/interfaces/IUniversalOracleBase.sol";
import {IStalenessChecker} from "src/modules/interfaces/IStalenessChecker.sol";
import {IStalenessCheckerWithHolidays} from "src/modules/interfaces/IStalenessCheckerWithHolidays.sol";

import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {ETTimestamp} from "src/libraries/ETTimestamp.sol";
import {StalenessCheckerWrapper} from "test/mocks/wrappers/StalenessCheckerWrapper.sol";
import {StalenessCheckerWithHolidaysWrapper} from "test/mocks/wrappers/StalenessCheckerWithHolidaysWrapper.sol";
import {MockAggregator} from "test/mocks/MockAggregator.sol";
import {TimeFixtures as T} from "test/utils/TimeFixtures.sol";

contract StalenessCheckerWithHolidaysTest is Test {
    MockAggregator internal feed;
    StalenessCheckerWithHolidaysWrapper internal oracle;

    uint256 internal constant MAX = 4 days;
    uint256 internal constant TRADING = 1 hours;
    uint256 internal constant REOPEN = 30 minutes;

    // DayType as uint8 (see StalenessCheckerWithHolidaysWrapper)
    uint8 internal constant REGULAR = 0;
    uint8 internal constant HOLIDAY = 1;
    uint8 internal constant WEEKEND = 2;

    // ------------------------------------------------------------ fixtures (Python zoneinfo("America/New_York"))
    // Thanksgiving 2024: Thursday 2024-11-28 (EST)
    uint256 internal constant TG_TUE_NOON = 1732640400; // Tue 2024-11-26 12:00 EST
    uint256 internal constant TG_WED_CLOSE = 1732755600; // Wed 2024-11-27 20:00 EST (= Thu 01:00 UTC)
    uint256 internal constant TG_THU_0000 = 1732770000; // Thu 2024-11-28 00:00 EST
    uint256 internal constant TG_THU_NOON = TG_THU_0000 + 12 hours;
    uint256 internal constant TG_THU_REOPEN = 1732842000; // Thu 2024-11-28 20:00 EST
    // Good Friday 2024: Friday 2024-03-29 (EDT)
    uint256 internal constant GF_THU_CLOSE = 1711670400; // Thu 2024-03-28 20:00 EDT
    uint256 internal constant GF_FRI_2000 = 1711756800; // Fri 2024-03-29 20:00 EDT
    uint256 internal constant GF_SUN_REOPEN = 1711929600; // Sun 2024-03-31 20:00 EDT
    uint256 internal constant APR_01_2024_2000 = 1712016000; // Mon 2024-04-01 20:00 EDT
    // Martin Luther King Jr. Day 2024: Monday 2024-01-15 (EST). The close before it is T.EST_FRI_2000.
    uint256 internal constant MLK_REOPEN = 1705366800; // Mon 2024-01-15 20:00 EST
    // New Year 2025: Wednesday 2025-01-01 (EST). The close is in UTC year 2025.
    uint256 internal constant NY_CLOSE = 1735693200; // Tue 2024-12-31 20:00 EST (= 2025-01-01 01:00 UTC)
    uint256 internal constant NY_REOPEN = 1735779600; // Wed 2025-01-01 20:00 EST
    // Independence Day 2024 (Thursday 2024-07-04), with Friday 2024-07-05 also set as a holiday (EDT)
    uint256 internal constant JUL_WED_CLOSE = 1720051200; // Wed 2024-07-03 20:00 EDT
    uint256 internal constant JUL_FRI_2000 = 1720224000; // Fri 2024-07-05 20:00 EDT
    uint256 internal constant JUL_SUN_REOPEN = 1720396800; // Sun 2024-07-07 20:00 EDT
    // New Year 2024 on a Monday: the close before it is in 2023
    uint256 internal constant DEC_29_2023_CLOSE = 1703898000; // Fri 2023-12-29 20:00 EST
    // Monday holidays next to the DST switches (synthetic)
    uint256 internal constant SPRING_FRI_CLOSE = 1709946000; // Fri 2024-03-08 20:00 EST
    uint256 internal constant SPRING_MON_REOPEN = 1710201600; // Mon 2024-03-11 20:00 EDT
    uint256 internal constant FALL_FRI_CLOSE = 1730505600; // Fri 2024-11-01 20:00 EDT
    uint256 internal constant FALL_MON_REOPEN = 1730768400; // Mon 2024-11-04 20:00 EST

    function setUp() public {
        vm.warp(TG_TUE_NOON);
        feed = new MockAggregator(8, "MSFT / USD");
        feed.setAnswer(400e8, block.timestamp);
        oracle = new StalenessCheckerWithHolidaysWrapper(address(feed), MAX, TRADING, REOPEN);
    }

    // ------------------------------------------------------------ helpers

    /// @dev startedAt is deliberately 0 (never equal to updatedAt), see StalenessChecker.t.sol.
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

    /// @dev At `_now`, a price that was exactly `TRADING` old at `_close` is accepted, one second older is rejected.
    function _assertLastClose(uint256 _now, uint256 _close) internal {
        _expectOk(_now, _close - TRADING);
        _expectRevert(_now, _close - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
    }

    function _bounds2024() internal pure returns (uint256, uint256) {
        return (T.DST_START_2024, T.DST_END_2024);
    }

    // ================================================================== constructor

    function test_constructor_SetsImmutables() public view {
        assertEq(oracle.maxStaleness(), MAX);
        assertEq(oracle.tradingStaleness(), TRADING);
        assertEq(oracle.reopenTimeWait(), REOPEN);
        assertEq(oracle.MAX_REOPEN_TIME_WAIT(), 4 hours);
        assertEq(oracle.owner(), address(this));
    }

    function test_constructor_ReopenTimeWaitJustBelowMax() public {
        StalenessCheckerWithHolidaysWrapper o =
            new StalenessCheckerWithHolidaysWrapper(address(feed), 1 days, 5 hours, 4 hours - 1);
        assertEq(o.reopenTimeWait(), 4 hours - 1);
    }

    function test_RevertWhen_constructor_ReopenTimeWaitEqualsMax() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IStalenessCheckerWithHolidays.ReopenTimeWaitGreaterThanOrEqualToMaxReopenTimeWait.selector
            )
        );
        new StalenessCheckerWithHolidaysWrapper(address(feed), 1 days, 5 hours, 4 hours);
    }

    function test_RevertWhen_constructor_BaseChecksRunFirst() public {
        // 5h is above MAX_REOPEN_TIME_WAIT too, but the StalenessChecker constructor runs first.
        vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.ReopenTimeWaitGreaterThanTradingStaleness.selector));
        new StalenessCheckerWithHolidaysWrapper(address(feed), 1 days, 1 hours, 5 hours);
    }

    function testFuzz_constructor(uint256 _max, uint256 _trading, uint256 _reopen) public {
        bytes4 err;
        if (_max == 0) err = IStalenessChecker.MaxStalenessZero.selector;
        else if (_trading == 0) err = IStalenessChecker.TradingStalenessZero.selector;
        else if (_max < _trading) err = IStalenessChecker.MaxStalenessLessThanTradingStaleness.selector;
        else if (_reopen > _trading) err = IStalenessChecker.ReopenTimeWaitGreaterThanTradingStaleness.selector;
        else if (_reopen >= 4 hours) {
            err = IStalenessCheckerWithHolidays.ReopenTimeWaitGreaterThanOrEqualToMaxReopenTimeWait.selector;
        }

        if (err != bytes4(0)) vm.expectRevert(abi.encodeWithSelector(err));
        StalenessCheckerWithHolidaysWrapper o =
            new StalenessCheckerWithHolidaysWrapper(address(feed), _max, _trading, _reopen);
        if (err == bytes4(0)) {
            assertEq(o.maxStaleness(), _max);
            assertEq(o.tradingStaleness(), _trading);
            assertEq(o.reopenTimeWait(), _reopen);
        }
    }

    // ================================================================== setHolidayET

    function test_setHolidayET_SetsAndClears() public {
        assertFalse(oracle.exposed_checkIsHolidayET(2024, 11, 28));

        vm.expectEmit(true, true, true, true, address(oracle));
        emit IStalenessCheckerWithHolidays.HolidaySet(2024, 11, 28, true);
        oracle.setHolidayET(2024, 11, 28, true);
        assertTrue(oracle.exposed_checkIsHolidayET(2024, 11, 28));
        assertFalse(oracle.exposed_checkIsHolidayET(2024, 11, 27), "neighbour day");
        assertFalse(oracle.exposed_checkIsHolidayET(2025, 11, 28), "same day, other year");

        vm.expectEmit(true, true, true, true, address(oracle));
        emit IStalenessCheckerWithHolidays.HolidaySet(2024, 11, 28, false);
        oracle.setHolidayET(2024, 11, 28, false);
        assertFalse(oracle.exposed_checkIsHolidayET(2024, 11, 28));
    }

    function test_setHolidayET_KeyIsAbiEncodedDate() public {
        oracle.setHolidayET(2024, 11, 28, true);
        bytes32 key = keccak256(abi.encode(uint256(2024), uint256(11), uint256(28)));
        assertEq(oracle.exposed_getHolidayKey(2024, 11, 28), key);
        assertTrue(oracle.isHolidayET(key));
        assertFalse(oracle.isHolidayET(keccak256(abi.encode(uint256(2024), uint256(28), uint256(11)))), "day/month swapped");
    }

    function test_setHolidayET_SameValueAndPastDateAccepted() public {
        oracle.setHolidayET(2024, 11, 28, true);
        oracle.setHolidayET(2024, 11, 28, true);
        oracle.setHolidayET(2000, 1, 3, true); // a Monday in the past
        assertTrue(oracle.exposed_checkIsHolidayET(2024, 11, 28));
        assertTrue(oracle.exposed_checkIsHolidayET(2000, 1, 3));
    }

    function test_RevertWhen_setHolidayET_NotOwner() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        oracle.setHolidayET(2024, 11, 28, true);
    }

    function test_RevertWhen_setHolidayET_WeekendDay() public {
        bytes memory err =
            abi.encodeWithSelector(IStalenessCheckerWithHolidays.WeekendDayCannotBeSetAsHoliday.selector);
        vm.expectRevert(err);
        oracle.setHolidayET(2024, 11, 30, true); // Saturday
        vm.expectRevert(err);
        oracle.setHolidayET(2024, 12, 1, true); // Sunday
        vm.expectRevert(err);
        oracle.setHolidayET(2024, 12, 1, false); // clearing a weekend day also reverts
    }

    function test_RevertWhen_setHolidayET_InvalidDate() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        oracle.setHolidayET(1969, 12, 31, true);
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        oracle.setHolidayET(10000, 1, 3, true);
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidMonth.selector));
        oracle.setHolidayET(2024, 13, 1, true);
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidDay.selector));
        oracle.setHolidayET(2023, 2, 29, true);
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidDay.selector));
        oracle.setHolidayET(2024, 1, 0, true);
    }

    function testFuzz_setHolidayET(uint256 _year, uint256 _month, uint256 _day) public {
        _year = bound(_year, 1970, 9999);
        _month = bound(_month, 1, 12);
        _day = bound(_day, 1, 28);
        if (UnixTimestamp.isWeekendDay(UnixTimestamp.getTimestamp(_year, _month, _day))) {
            vm.expectRevert(
                abi.encodeWithSelector(IStalenessCheckerWithHolidays.WeekendDayCannotBeSetAsHoliday.selector)
            );
            oracle.setHolidayET(_year, _month, _day, true);
        } else {
            oracle.setHolidayET(_year, _month, _day, true);
            assertTrue(oracle.isHolidayET(keccak256(abi.encode(_year, _month, _day))));
        }
    }

    // ================================================================== _isETHolidayTrading

    function test_isETHolidayTrading_Thanksgiving() public {
        oracle.setHolidayET(2024, 11, 28, true);
        (uint256 s, uint256 e) = _bounds2024();
        assertFalse(oracle.exposed_isETHolidayTrading(TG_TUE_NOON, s, e, REOPEN), "Tue 12:00");
        assertFalse(oracle.exposed_isETHolidayTrading(TG_WED_CLOSE - 1, s, e, REOPEN), "Wed 19:59:59");
        assertTrue(oracle.exposed_isETHolidayTrading(TG_WED_CLOSE, s, e, REOPEN), "Wed 20:00");
        assertTrue(oracle.exposed_isETHolidayTrading(TG_THU_0000 - 1, s, e, REOPEN), "Wed 23:59:59");
        assertTrue(oracle.exposed_isETHolidayTrading(TG_THU_0000, s, e, REOPEN), "Thu 00:00");
        assertTrue(oracle.exposed_isETHolidayTrading(TG_THU_REOPEN - 1, s, e, REOPEN), "Thu 19:59:59");
        assertTrue(oracle.exposed_isETHolidayTrading(TG_THU_REOPEN, s, e, REOPEN), "Thu 20:00");
        assertTrue(oracle.exposed_isETHolidayTrading(TG_THU_REOPEN + REOPEN - 1, s, e, REOPEN), "grace - 1");
        assertFalse(oracle.exposed_isETHolidayTrading(TG_THU_REOPEN + REOPEN, s, e, REOPEN), "grace");
        assertFalse(oracle.exposed_isETHolidayTrading(TG_THU_REOPEN + 4 hours, s, e, REOPEN), "Fri 00:00");
    }

    function test_isETHolidayTrading_NoHolidaySet() public view {
        (uint256 s, uint256 e) = _bounds2024();
        assertFalse(oracle.exposed_isETHolidayTrading(TG_WED_CLOSE, s, e, REOPEN));
        assertFalse(oracle.exposed_isETHolidayTrading(TG_THU_NOON, s, e, REOPEN));
        assertFalse(oracle.exposed_isETHolidayTrading(TG_THU_REOPEN, s, e, REOPEN));
    }

    function test_isETHolidayTrading_GraceZero() public {
        oracle.setHolidayET(2024, 11, 28, true);
        (uint256 s, uint256 e) = _bounds2024();
        assertTrue(oracle.exposed_isETHolidayTrading(TG_THU_REOPEN - 1, s, e, 0));
        assertFalse(oracle.exposed_isETHolidayTrading(TG_THU_REOPEN, s, e, 0));
    }

    function test_isETHolidayTrading_GraceEndsAtMidnight() public {
        // A grace period of 4 hours or more ends at 00:00 ET of the next day.
        oracle.setHolidayET(2024, 11, 28, true);
        (uint256 s, uint256 e) = _bounds2024();
        assertTrue(oracle.exposed_isETHolidayTrading(TG_THU_REOPEN + 4 hours - 1, s, e, 10 hours), "Thu 23:59:59");
        assertFalse(oracle.exposed_isETHolidayTrading(TG_THU_REOPEN + 4 hours, s, e, 10 hours), "Fri 00:00");
    }

    function test_isETHolidayTrading_ConsecutiveHolidays() public {
        oracle.setHolidayET(2024, 7, 4, true);
        oracle.setHolidayET(2024, 7, 5, true);
        (uint256 s, uint256 e) = _bounds2024();
        uint256 thuReopen = JUL_FRI_2000 - 1 days;
        assertTrue(oracle.exposed_isETHolidayTrading(thuReopen + REOPEN, s, e, REOPEN), "Thu after grace: Fri closed");
        assertTrue(oracle.exposed_isETHolidayTrading(JUL_FRI_2000 - 1, s, e, REOPEN), "Fri 19:59:59");
        assertTrue(oracle.exposed_isETHolidayTrading(JUL_FRI_2000, s, e, REOPEN), "Fri 20:00, grace");
        assertFalse(oracle.exposed_isETHolidayTrading(JUL_FRI_2000 + REOPEN, s, e, REOPEN), "Fri after grace");
    }

    function test_isETHolidayTrading_NewYearAcrossUTCYear() public {
        // Tue 2024-12-31 20:30 ET is 2025-01-01 01:30 UTC: the caller passes the 2025 DST boundaries.
        oracle.setHolidayET(2025, 1, 1, true);
        (uint256 s, uint256 e) = ETTimestamp.getETTransitionBoundariesInUTC(2025);
        (uint256 s24, uint256 e24) = _bounds2024();
        assertFalse(oracle.exposed_isETHolidayTrading(NY_CLOSE - 1, s24, e24, REOPEN), "Tue 19:59:59");
        assertTrue(oracle.exposed_isETHolidayTrading(NY_CLOSE, s, e, REOPEN), "Tue 20:00");
        assertTrue(oracle.exposed_isETHolidayTrading(NY_CLOSE + 30 minutes, s, e, REOPEN), "Tue 20:30");
        assertTrue(oracle.exposed_isETHolidayTrading(NY_REOPEN - 1, s, e, REOPEN), "Wed 19:59:59");
        assertFalse(oracle.exposed_isETHolidayTrading(NY_REOPEN + REOPEN, s, e, REOPEN), "Wed after grace");
    }

    function test_RevertWhen_isETHolidayTrading_Year9999() public {
        (uint256 s, uint256 e) = ETTimestamp.getETTransitionBoundariesInUTC(9999);
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        oracle.exposed_isETHolidayTrading(T.DEC_31_9999 + 12 hours, s, e, REOPEN);
    }

    // ================================================================== _getLastETCloseTimestampInUTC

    function test_getLastETCloseTimestampInUTC_Regular() public view {
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 11, 27, REGULAR), TG_WED_CLOSE, "EST");
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 3, 28, REGULAR), GF_THU_CLOSE, "EDT");
    }

    function test_getLastETCloseTimestampInUTC_HolidayAfterRegularDay() public {
        oracle.setHolidayET(2024, 11, 28, true);
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 11, 28, HOLIDAY), TG_WED_CLOSE);
    }

    function test_getLastETCloseTimestampInUTC_HolidayAfterWeekend() public {
        oracle.setHolidayET(2024, 1, 15, true);
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 1, 15, HOLIDAY), T.EST_FRI_2000);
    }

    function test_getLastETCloseTimestampInUTC_HolidayAfterHoliday() public {
        oracle.setHolidayET(2024, 7, 4, true);
        oracle.setHolidayET(2024, 7, 5, true);
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 7, 5, HOLIDAY), JUL_WED_CLOSE);
    }

    function test_getLastETCloseTimestampInUTC_WeekendAfterRegularFriday() public view {
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 6, 8, WEEKEND), T.EDT_FRI_2000, "Saturday");
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 6, 9, WEEKEND), T.EDT_FRI_2000, "Sunday");
    }

    function test_getLastETCloseTimestampInUTC_WeekendAfterHolidayFriday() public {
        oracle.setHolidayET(2024, 3, 29, true);
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 3, 30, WEEKEND), GF_THU_CLOSE, "Saturday");
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 3, 31, WEEKEND), GF_THU_CLOSE, "Sunday");
    }

    function test_getLastETCloseTimestampInUTC_WeekendAfterTwoHolidays() public {
        oracle.setHolidayET(2024, 7, 4, true);
        oracle.setHolidayET(2024, 7, 5, true);
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 7, 6, WEEKEND), JUL_WED_CLOSE);
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 7, 7, WEEKEND), JUL_WED_CLOSE);
    }

    function test_getLastETCloseTimestampInUTC_HolidaysAroundWeekend() public {
        // Friday and Monday holidays: Monday -> Sunday -> Saturday -> Friday (holiday) -> Thursday.
        oracle.setHolidayET(2024, 3, 29, true);
        oracle.setHolidayET(2024, 4, 1, true);
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 4, 1, HOLIDAY), GF_THU_CLOSE);
    }

    function test_getLastETCloseTimestampInUTC_AcrossYearBoundary() public {
        oracle.setHolidayET(2024, 1, 1, true); // Monday
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 1, 1, HOLIDAY), DEC_29_2023_CLOSE);
    }

    function test_getLastETCloseTimestampInUTC_AcrossDSTSwitch() public {
        oracle.setHolidayET(2024, 3, 11, true); // Monday after the switch to EDT, close in EST
        oracle.setHolidayET(2024, 11, 4, true); // Monday after the switch to EST, close in EDT
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 3, 11, HOLIDAY), SPRING_FRI_CLOSE, "spring");
        assertEq(oracle.exposed_getLastETCloseTimestampInUTC(2024, 11, 4, HOLIDAY), FALL_FRI_CLOSE, "fall");
    }

    function test_RevertWhen_getLastETCloseTimestampInUTC_Year1970() public {
        oracle.setHolidayET(1970, 1, 5, true); // Monday
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        oracle.exposed_getLastETCloseTimestampInUTC(1970, 1, 5, HOLIDAY);
    }

    // ================================================================== _afterRead: holidays

    function test_afterRead_Thanksgiving() public {
        oracle.setHolidayET(2024, 11, 28, true);
        // Before the close the market trades.
        _expectRevert(TG_WED_CLOSE - 1, TG_WED_CLOSE - 1 - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
        // From the close to the end of the reopen grace period, the price must be fresh at the Wednesday close.
        _assertLastClose(TG_WED_CLOSE, TG_WED_CLOSE);
        _assertLastClose(TG_THU_0000, TG_WED_CLOSE);
        _assertLastClose(TG_THU_NOON, TG_WED_CLOSE);
        _assertLastClose(TG_THU_REOPEN - 1, TG_WED_CLOSE);
        _assertLastClose(TG_THU_REOPEN, TG_WED_CLOSE);
        _assertLastClose(TG_THU_REOPEN + REOPEN - 1, TG_WED_CLOSE);
        // After the grace period the market trades again.
        _expectRevert(TG_THU_REOPEN + REOPEN, TG_WED_CLOSE, IStalenessChecker.TradingStalenessReached.selector);
        _expectOk(TG_THU_REOPEN + REOPEN, TG_THU_REOPEN + REOPEN - TRADING);
    }

    function test_RevertWhen_afterRead_HolidayNotSet() public {
        _expectRevert(TG_THU_NOON, TG_WED_CLOSE, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_RevertWhen_afterRead_HolidayCleared() public {
        oracle.setHolidayET(2024, 11, 28, true);
        _expectOk(TG_THU_NOON, TG_WED_CLOSE);
        oracle.setHolidayET(2024, 11, 28, false);
        _expectRevert(TG_THU_NOON, TG_WED_CLOSE, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_FreshPriceOnHolidayAccepted() public {
        oracle.setHolidayET(2024, 11, 28, true);
        _expectOk(TG_THU_NOON, TG_THU_NOON - TRADING);
        _expectOk(TG_THU_NOON, TG_THU_NOON);
    }

    function test_RevertWhen_afterRead_MaxStalenessOnHoliday() public {
        oracle.setHolidayET(2024, 11, 28, true);
        _expectRevert(TG_THU_NOON, TG_THU_NOON - MAX - 1, IStalenessChecker.MaxStalenessReached.selector);
    }

    function test_afterRead_GoodFriday() public {
        oracle.setHolidayET(2024, 3, 29, true);
        _expectRevert(GF_THU_CLOSE - 1, GF_THU_CLOSE - 1 - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
        _assertLastClose(GF_THU_CLOSE, GF_THU_CLOSE);
        _assertLastClose(GF_FRI_2000 - 8 hours, GF_THU_CLOSE); // Fri 12:00
        _assertLastClose(GF_FRI_2000 + 1 hours, GF_THU_CLOSE); // Fri 21:00, weekend closure
        _assertLastClose(GF_FRI_2000 + 16 hours, GF_THU_CLOSE); // Sat 12:00
        _assertLastClose(GF_SUN_REOPEN - 1, GF_THU_CLOSE);
        _assertLastClose(GF_SUN_REOPEN + REOPEN - 1, GF_THU_CLOSE);
        _expectRevert(GF_SUN_REOPEN + REOPEN, GF_THU_CLOSE, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_MondayHoliday() public {
        oracle.setHolidayET(2024, 1, 15, true);
        uint256 close = T.EST_FRI_2000;
        _assertLastClose(T.EST_FRI_2000 + 16 hours, close); // Sat 12:00
        // The weekend grace period is over, but the Monday session is closed.
        _assertLastClose(T.EST_SUN_2000 + REOPEN, close);
        _assertLastClose(T.EST_NEXT_MON_0000 + 12 hours, close); // Mon 12:00
        _assertLastClose(MLK_REOPEN - 1, close);
        _assertLastClose(MLK_REOPEN + REOPEN - 1, close);
        _expectRevert(MLK_REOPEN + REOPEN, close, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_NewYearAcrossUTCYear() public {
        oracle.setHolidayET(2025, 1, 1, true);
        _expectRevert(NY_CLOSE - 1, NY_CLOSE - 1 - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
        _assertLastClose(NY_CLOSE, NY_CLOSE); // 2025-01-01 01:00 UTC, still 2024 in ET
        _assertLastClose(NY_CLOSE + 3 hours, NY_CLOSE); // Wed 2025-01-01 00:00 ET
        _assertLastClose(NY_REOPEN - 8 hours, NY_CLOSE); // Wed 12:00
        _assertLastClose(NY_REOPEN + REOPEN - 1, NY_CLOSE);
        _expectRevert(NY_REOPEN + REOPEN, NY_CLOSE, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_TwoHolidaysBeforeWeekend() public {
        // Wed 20:00 -> Sun 20:30 is more than 4 days, so this test uses a larger maxStaleness.
        oracle = new StalenessCheckerWithHolidaysWrapper(address(feed), 10 days, TRADING, REOPEN);
        oracle.setHolidayET(2024, 7, 4, true);
        oracle.setHolidayET(2024, 7, 5, true);
        _assertLastClose(JUL_WED_CLOSE, JUL_WED_CLOSE);
        _assertLastClose(JUL_FRI_2000 - 1 days + REOPEN, JUL_WED_CLOSE); // Thu after its grace period
        _assertLastClose(JUL_FRI_2000 + 16 hours, JUL_WED_CLOSE); // Sat 12:00
        _assertLastClose(JUL_SUN_REOPEN + REOPEN - 1, JUL_WED_CLOSE);
        _expectRevert(JUL_SUN_REOPEN + REOPEN, JUL_WED_CLOSE, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_HolidaysAroundWeekend() public {
        oracle = new StalenessCheckerWithHolidaysWrapper(address(feed), 10 days, TRADING, REOPEN);
        oracle.setHolidayET(2024, 3, 29, true);
        oracle.setHolidayET(2024, 4, 1, true);
        _assertLastClose(GF_SUN_REOPEN + REOPEN, GF_THU_CLOSE); // Sun after the weekend grace period
        _assertLastClose(APR_01_2024_2000 - 8 hours, GF_THU_CLOSE); // Mon 12:00
        _assertLastClose(APR_01_2024_2000 + REOPEN - 1, GF_THU_CLOSE);
        _expectRevert(APR_01_2024_2000 + REOPEN, GF_THU_CLOSE, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_MondayHolidayAfterSpringForward() public {
        oracle.setHolidayET(2024, 3, 11, true);
        _assertLastClose(SPRING_MON_REOPEN - 8 hours, SPRING_FRI_CLOSE); // Mon 12:00 EDT
        _assertLastClose(SPRING_MON_REOPEN + REOPEN - 1, SPRING_FRI_CLOSE);
        _expectRevert(SPRING_MON_REOPEN + REOPEN, SPRING_FRI_CLOSE, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_MondayHolidayAfterFallBack() public {
        oracle.setHolidayET(2024, 11, 4, true);
        _assertLastClose(FALL_MON_REOPEN - 8 hours, FALL_FRI_CLOSE); // Mon 12:00 EST
        _assertLastClose(FALL_MON_REOPEN + REOPEN - 1, FALL_FRI_CLOSE);
        _expectRevert(FALL_MON_REOPEN + REOPEN, FALL_FRI_CLOSE, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_afterRead_WeekendWithoutHolidays() public {
        // The weekend rules of StalenessChecker still apply.
        _assertLastClose(T.EDT_FRI_2000 + 16 hours, T.EDT_FRI_2000);
        _assertLastClose(T.EDT_SUN_2000 + REOPEN - 1, T.EDT_FRI_2000);
        _expectRevert(T.EDT_SUN_2000 + REOPEN, T.EDT_FRI_2000, IStalenessChecker.TradingStalenessReached.selector);
    }

    function test_RevertWhen_afterRead_Year9999() public {
        // The holiday check is reached only when the trading staleness window has elapsed.
        uint256 t = T.DEC_31_9999 + 12 hours;
        _expectOk(t, t - TRADING);
        _expectRevert(t, t - TRADING - 1, UnixTimestamp.InvalidYear.selector);
    }

    // ================================================================== end-to-end through _price

    function test_price_OnHoliday() public {
        oracle.setHolidayET(2024, 11, 28, true);
        vm.warp(TG_THU_NOON);
        feed.setAnswer(400e8, TG_WED_CLOSE - TRADING);
        assertEq(oracle.exposed_price(), 400e8);
        feed.setAnswer(400e8, TG_WED_CLOSE - TRADING - 1);
        vm.expectRevert(abi.encodeWithSelector(IStalenessChecker.TradingStalenessReached.selector));
        oracle.exposed_price();
    }

    // ================================================================== fuzz

    /// @dev With no holiday set, the module behaves exactly like StalenessChecker.
    function testFuzz_afterRead_NoHolidaysMatchesStalenessChecker(uint256 _now, uint256 _age, uint256 _reopen) public {
        _now = bound(_now, 1168214400, 4102444799); // 2007-01-08 .. 2099-12-31
        _age = bound(_age, 0, MAX + 1 hours);
        _reopen = bound(_reopen, 0, TRADING);
        StalenessCheckerWrapper base = new StalenessCheckerWrapper(address(feed), MAX, TRADING, _reopen);
        StalenessCheckerWithHolidaysWrapper holidays =
            new StalenessCheckerWithHolidaysWrapper(address(feed), MAX, TRADING, _reopen);

        vm.warp(_now);
        bytes memory data = abi.encodeCall(StalenessCheckerWrapper.exposed_afterRead, (_round(1, _now - _age)));
        (bool okBase, bytes memory retBase) = address(base).staticcall(data);
        (bool okHolidays, bytes memory retHolidays) = address(holidays).staticcall(data);
        assertEq(okHolidays, okBase, "success");
        assertEq(retHolidays, retBase, "revert data");
    }

    /// @dev Random holidays in a 4-week window. When the market is closed, the last close must be 20:00 ET on a
    ///      trading day, at or before now, and every day between it and the current session must be closed.
    ///      The price threshold of `_afterRead` must be exactly that close.
    function testFuzz_afterRead_RandomHolidays(uint256 _week, uint256 _mask, uint256 _offset) public {
        oracle = new StalenessCheckerWithHolidaysWrapper(address(feed), 30 days, TRADING, REOPEN);
        uint256 monday = 1168214400 + bound(_week, 0, 4500) * 7 days; // Mondays from 2007-01-08
        _mask = bound(_mask, 0, (1 << 28) - 1);
        for (uint256 i = 0; i < 28; i++) {
            if ((_mask >> i) & 1 == 1 && !UnixTimestamp.isWeekendDay(monday + i * 1 days)) {
                (uint256 y, uint256 m, uint256 d) = UnixTimestamp.getDate(monday + i * 1 days);
                oracle.setHolidayET(y, m, d, true);
            }
        }
        uint256 nowTs = monday + 7 days + bound(_offset, 0, 14 days);

        (uint256 year,,) = UnixTimestamp.getDate(nowTs);
        (uint256 s, uint256 e) = ETTimestamp.getETTransitionBoundariesInUTC(year);
        bool closed = oracle.exposed_isETWeekendTrading(nowTs, s, e, REOPEN)
            || oracle.exposed_isETHolidayTrading(nowTs, s, e, REOPEN);

        if (!closed) {
            _expectRevert(nowTs, nowTs - TRADING - 1, IStalenessChecker.TradingStalenessReached.selector);
            return;
        }

        uint256 nowET = ETTimestamp.toETTimestamp(nowTs, s, e);
        uint256 close = oracle.exposed_getLastETCloseTimestampInUTC(_etYear(nowET), _etMonth(nowET), _etDay(nowET), _dayType(nowET));
        assertLe(close, nowTs, "close in the future");

        (uint256 cs, uint256 ce) = ETTimestamp.getETTransitionBoundariesInUTC(_utcYear(close));
        uint256 closeET = ETTimestamp.toETTimestamp(close, cs, ce);
        assertEq(closeET % 1 days, 20 hours, "close is not 20:00 ET");
        assertTrue(_isTradingDay(closeET / 1 days), "close is not on a trading day");

        uint256 sessionDay = nowET / 1 days + (nowET % 1 days >= 20 hours ? 1 : 0);
        assertLt(closeET / 1 days, sessionDay, "close is not before the current session");
        for (uint256 day = closeET / 1 days + 1; day < sessionDay; day++) {
            assertFalse(_isTradingDay(day), "an open trading day was skipped");
        }

        _assertLastClose(nowTs, close);
    }

    function _isTradingDay(uint256 _etDayNumber) internal view returns (bool) {
        uint256 ts = _etDayNumber * 1 days;
        if (UnixTimestamp.isWeekendDay(ts)) return false;
        (uint256 y, uint256 m, uint256 d) = UnixTimestamp.getDate(ts);
        return !oracle.exposed_checkIsHolidayET(y, m, d);
    }

    function _dayType(uint256 _etTimestamp) internal view returns (uint8) {
        if (UnixTimestamp.isWeekendDay(_etTimestamp)) return WEEKEND;
        (uint256 y, uint256 m, uint256 d) = UnixTimestamp.getDate(_etTimestamp);
        return oracle.exposed_checkIsHolidayET(y, m, d) ? HOLIDAY : REGULAR;
    }

    function _utcYear(uint256 _ts) internal pure returns (uint256 y) {
        (y,,) = UnixTimestamp.getDate(_ts);
    }

    function _etYear(uint256 _etTimestamp) internal pure returns (uint256 y) {
        (y,,) = UnixTimestamp.getDate(_etTimestamp);
    }

    function _etMonth(uint256 _etTimestamp) internal pure returns (uint256 m) {
        (, m,) = UnixTimestamp.getDate(_etTimestamp);
    }

    function _etDay(uint256 _etTimestamp) internal pure returns (uint256 d) {
        (,, d) = UnixTimestamp.getDate(_etTimestamp);
    }
}
