// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IUniversalOracleBase} from "src/interfaces/IUniversalOracleBase.sol";
import {ITransitionCheckerWithHolidays} from "src/modules/interfaces/ITransitionCheckerWithHolidays.sol";
import {ITransitionManager} from "src/modules/shared/interfaces/ITransitionManager.sol";
import {IMarketHoliday} from "src/modules/shared/interfaces/IMarketHoliday.sol";

import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {ETTimestamp} from "src/libraries/ETTimestamp.sol";
import {TransitionCheckerWithHolidaysWrapper} from "test/mocks/wrappers/TransitionCheckerWithHolidaysWrapper.sol";
import {MockAggregator} from "test/mocks/MockAggregator.sol";
import {TimeFixtures as T} from "test/utils/TimeFixtures.sol";

contract TransitionCheckerWithHolidaysTest is Test {
    MockAggregator internal feed;
    TransitionCheckerWithHolidaysWrapper internal oracle;

    uint256 internal constant WINDOW = 10 minutes;
    uint256 internal constant MAX_WINDOW = 4 hours;

    // Transition as uint8 (see ITransitionManager.Transition)
    uint8 internal constant OVERNIGHT_TO_PRE = 0;
    uint8 internal constant PRE_TO_REGULAR = 1;
    uint8 internal constant REGULAR_TO_POST = 2;
    uint8 internal constant POST_TO_OVERNIGHT = 3;

    uint256 internal constant AT_0400 = 4 hours;
    uint256 internal constant AT_0930 = 9 hours + 30 minutes;
    uint256 internal constant AT_1600 = 16 hours;
    uint256 internal constant AT_2000 = 20 hours;

    // ------------------------------------------------------------ fixtures (Python zoneinfo("America/New_York"))
    uint256 internal constant EDT_WED_0000 = 1717560000; // Wed 2024-06-05 00:00 EDT
    uint256 internal constant EST_WED_0000 = 1704862800; // Wed 2024-01-10 00:00 EST
    // DST switches: Sunday 20:00 and Monday 04:00 after each switch
    uint256 internal constant DST_START_SUN_2000 = 1710115200; // Sun 2024-03-10 20:00 EDT
    uint256 internal constant DST_START_MON_0400 = 1710144000; // Mon 2024-03-11 04:00 EDT
    uint256 internal constant DST_END_SUN_2000 = 1730682000; // Sun 2024-11-03 20:00 EST
    uint256 internal constant DST_END_MON_0400 = 1730710800; // Mon 2024-11-04 04:00 EST
    // Thanksgiving 2024: Thursday 2024-11-28 (EST)
    uint256 internal constant TG_WED_0000 = 1732683600; // Wed 2024-11-27 00:00 EST
    uint256 internal constant TG_THU_0000 = 1732770000; // Thu 2024-11-28 00:00 EST
    uint256 internal constant TG_FRI_0000 = 1732856400; // Fri 2024-11-29 00:00 EST
    // Independence Day 2024 (Thursday 2024-07-04), with Friday 2024-07-05 also set as a holiday (EDT)
    uint256 internal constant JUL_WED_0000 = 1719979200; // Wed 2024-07-03 00:00 EDT
    uint256 internal constant JUL_THU_0000 = 1720065600; // Thu 2024-07-04 00:00 EDT
    uint256 internal constant JUL_FRI_0000 = 1720152000; // Fri 2024-07-05 00:00 EDT
    uint256 internal constant JUL_SUN_2000 = 1720396800; // Sun 2024-07-07 20:00 EDT
    // Good Friday 2024: Friday 2024-03-29 (EDT)
    uint256 internal constant GF_THU_2000 = 1711670400; // Thu 2024-03-28 20:00 EDT
    uint256 internal constant GF_FRI_0000 = 1711684800; // Fri 2024-03-29 00:00 EDT
    uint256 internal constant GF_SUN_2000 = 1711929600; // Sun 2024-03-31 20:00 EDT
    // Martin Luther King Jr. Day 2024: Monday 2024-01-15 (EST)
    uint256 internal constant MLK_MON_0000 = 1705294800; // Mon 2024-01-15 00:00 EST
    uint256 internal constant MLK_TUE_0000 = 1705381200; // Tue 2024-01-16 00:00 EST
    // New Year 2025: Wednesday 2025-01-01 (EST). The Tuesday 20:00 boundary is in UTC year 2025.
    uint256 internal constant NY_TUE_2000 = 1735693200; // Tue 2024-12-31 20:00 EST (= 2025-01-01 01:00 UTC)
    uint256 internal constant NY_WED_0000 = 1735707600; // Wed 2025-01-01 00:00 EST
    // Year 9999
    uint256 internal constant Y9999_FRI_NOON = 253401670800; // Fri 9999-12-24 12:00 EST
    uint256 internal constant Y9999_SAT_NOON = 253401757200; // Sat 9999-12-25 12:00 EST

    function setUp() public {
        vm.warp(EDT_WED_0000 + 12 hours);
        feed = new MockAggregator(8, "MSFT / USD");
        feed.setAnswer(400e8, block.timestamp);
        oracle = new TransitionCheckerWithHolidaysWrapper(address(feed), WINDOW);
    }

    // ------------------------------------------------------------ helpers

    /// @dev startedAt is deliberately 0 (never equal to updatedAt), see StalenessChecker.t.sol.
    function _round(int256 _answer, uint256 _updatedAt) internal pure returns (IUniversalOracleBase.RoundData memory) {
        return IUniversalOracleBase.RoundData(1, _answer, 0, _updatedAt, 1);
    }

    function _selector(uint8 _transition) internal pure returns (bytes4) {
        if (_transition == OVERNIGHT_TO_PRE) return ITransitionCheckerWithHolidays.TransitionOvernightToPreMarket.selector;
        if (_transition == PRE_TO_REGULAR) return ITransitionCheckerWithHolidays.TransitionPreMarketToRegular.selector;
        if (_transition == REGULAR_TO_POST) return ITransitionCheckerWithHolidays.TransitionRegularToPostMarket.selector;
        return ITransitionCheckerWithHolidays.TransitionPostMarketToOvernight.selector;
    }

    function _boundaryOf(uint8 _transition) internal pure returns (uint256) {
        return [AT_0400, AT_0930, AT_1600, AT_2000][_transition];
    }

    function _expectOk(uint256 _now) internal {
        vm.warp(_now);
        oracle.exposed_afterRead(_round(1, _now));
    }

    function _expectRevert(uint256 _now, bytes4 _selector_) internal {
        vm.warp(_now);
        vm.expectRevert(abi.encodeWithSelector(_selector_));
        oracle.exposed_afterRead(_round(1, _now));
    }

    /// @dev The transition is checked: the boundary is accepted, the window `(boundary, boundary + _window]` reverts
    ///      with the error of the transition, and the first second after the window is accepted.
    function _assertChecked(uint256 _boundary, uint8 _transition, uint256 _window) internal {
        _expectOk(_boundary);
        _expectRevert(_boundary + 1, _selector(_transition));
        _expectRevert(_boundary + _window, _selector(_transition));
        _expectOk(_boundary + _window + 1);
    }

    function _assertChecked(uint256 _boundary, uint8 _transition) internal {
        _assertChecked(_boundary, _transition, WINDOW);
    }

    /// @dev The transition is not checked: every second of its window is accepted.
    function _assertNotChecked(uint256 _boundary) internal {
        _expectOk(_boundary + 1);
        _expectOk(_boundary + WINDOW / 2);
        _expectOk(_boundary + WINDOW);
    }

    /// @dev Checks the four transitions of the ET date that starts at `_day0000` (00:00 ET, as a UTC timestamp).
    ///      No DST switch may be between 00:00 ET and 20:00 ET of this date.
    function _assertDay(uint256 _day0000, bool _morningChecks, bool _eveningCheck) internal {
        for (uint8 i = 0; i < 3; i++) {
            if (_morningChecks) _assertChecked(_day0000 + _boundaryOf(i), i);
            else _assertNotChecked(_day0000 + _boundaryOf(i));
        }
        if (_eveningCheck) _assertChecked(_day0000 + AT_2000, POST_TO_OVERNIGHT);
        else _assertNotChecked(_day0000 + AT_2000);
    }

    // ================================================================== constructor and constants

    function test_constructor_SetsDefaultWindow() public view {
        assertEq(oracle.defaultTransitionWindow(), WINDOW);
        assertEq(oracle.owner(), address(this));
        assertEq(address(oracle.aggregator()), address(feed));
    }

    function test_RevertWhen_constructor_DefaultWindowEqualsMax() public {
        vm.expectRevert(abi.encodeWithSelector(ITransitionManager.DefaultTransitionWindowTooLong.selector));
        new TransitionCheckerWithHolidaysWrapper(address(feed), MAX_WINDOW);
    }

    function test_RevertWhen_constructor_AggregatorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.AggregatorZeroAddress.selector));
        new TransitionCheckerWithHolidaysWrapper(address(0), WINDOW);
    }

    function test_constants() public view {
        assertEq(oracle.SUNDAY(), 6);
    }

    // ================================================================== TransitionManager integration
    // The window storage, the setters, _isTransition and _getTransitionOffset are tested in
    // test/modules/shared/TransitionManager.t.sol.

    function test_setTransitionWindow_InheritedFromTransitionManager() public {
        ITransitionManager.Transition t = ITransitionManager.Transition.PreMarketToRegular;
        vm.expectEmit(true, true, true, true, address(oracle));
        emit ITransitionManager.TransitionWindowSet(t, true, 1 hours);
        oracle.setTransitionWindow(t, true, 1 hours);
        (bool isSet, uint256 window) = oracle.transitionWindows(t);
        assertTrue(isSet);
        assertEq(window, 1 hours);
    }

    function test_setDefaultTransitionWindow_InheritedFromTransitionManager() public {
        vm.expectEmit(true, true, true, true, address(oracle));
        emit ITransitionManager.DefaultTransitionWindowSet(1 hours);
        oracle.setDefaultTransitionWindow(1 hours);
        assertEq(oracle.defaultTransitionWindow(), 1 hours);
    }

    function test_RevertWhen_setTransitionWindow_NotOwner() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        oracle.setTransitionWindow(ITransitionManager.Transition.OvernightToPreMarket, true, 1 hours);
    }

    function test_RevertWhen_setDefaultTransitionWindow_NotOwner() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        oracle.setDefaultTransitionWindow(1 hours);
    }

    // ================================================================== _afterRead: trading days

    function test_afterRead_RegularDayEDT() public {
        _assertDay(EDT_WED_0000, true, true);
    }

    function test_afterRead_RegularDayEST() public {
        _assertDay(EST_WED_0000, true, true);
    }

    function test_afterRead_OutsideWindowsAccepted() public {
        _expectOk(EDT_WED_0000);
        _expectOk(EDT_WED_0000 + 12 hours);
        _expectOk(EDT_WED_0000 + 1 days - 1);
    }

    function test_afterRead_FridayEveningNotChecked() public {
        // Friday is a trading day, but the market closes at 20:00 ET for the weekend.
        _assertDay(T.EDT_MON_0000 + 4 days, true, false);
    }

    function test_afterRead_SaturdayNotChecked() public {
        _assertDay(T.EDT_MON_0000 + 5 days, false, false);
    }

    function test_afterRead_SundayReopenChecked() public {
        _assertDay(T.EDT_MON_0000 + 6 days, false, true);
        _assertChecked(T.EDT_SUN_2000, POST_TO_OVERNIGHT);
    }

    function test_afterRead_MondayMorningChecked() public {
        _assertDay(T.EDT_NEXT_MON_0000, true, true);
    }

    function test_afterRead_DSTSwitchSundays() public {
        // The Sunday 20:00 reopen and the Monday 04:00 transition after each DST switch.
        _assertChecked(DST_START_SUN_2000, POST_TO_OVERNIGHT);
        _assertChecked(DST_START_MON_0400, OVERNIGHT_TO_PRE);
        _assertChecked(DST_END_SUN_2000, POST_TO_OVERNIGHT);
        _assertChecked(DST_END_MON_0400, OVERNIGHT_TO_PRE);
    }

    function test_afterRead_NewYearEveAcrossUTCYear() public {
        // 2024-12-31 20:00 EST is 2025-01-01 01:00 UTC. The ET date is still 2024-12-31.
        _assertChecked(NY_TUE_2000, POST_TO_OVERNIGHT);
        _assertDay(NY_WED_0000, true, true);
    }

    // ================================================================== _afterRead: holidays

    function test_afterRead_Thanksgiving() public {
        oracle.setHolidayET(2024, 11, 28, true);
        _assertDay(TG_WED_0000, true, false); // the market closes at 20:00 ET before the holiday
        _assertDay(TG_THU_0000, false, true); // only the 20:00 ET reopen is checked on the holiday
        _assertDay(TG_FRI_0000, true, false);
    }

    function test_afterRead_HolidayNotSet() public {
        _assertDay(TG_WED_0000, true, true);
        _assertDay(TG_THU_0000, true, true);
    }

    function test_afterRead_HolidayCleared() public {
        oracle.setHolidayET(2024, 11, 28, true);
        _assertNotChecked(TG_THU_0000 + AT_0930);
        oracle.setHolidayET(2024, 11, 28, false);
        _assertChecked(TG_THU_0000 + AT_0930, PRE_TO_REGULAR);
    }

    function test_afterRead_TwoHolidaysBeforeWeekend() public {
        oracle.setHolidayET(2024, 7, 4, true);
        oracle.setHolidayET(2024, 7, 5, true);
        _assertDay(JUL_WED_0000, true, false);
        _assertDay(JUL_THU_0000, false, false); // the next day is a holiday too
        _assertDay(JUL_FRI_0000, false, false); // the next day is a Saturday
        _assertChecked(JUL_SUN_2000, POST_TO_OVERNIGHT);
    }

    function test_afterRead_GoodFriday() public {
        oracle.setHolidayET(2024, 3, 29, true);
        _assertNotChecked(GF_THU_2000);
        _assertDay(GF_FRI_0000, false, false);
        _assertChecked(GF_SUN_2000, POST_TO_OVERNIGHT);
    }

    function test_afterRead_MondayHoliday() public {
        oracle.setHolidayET(2024, 1, 15, true);
        _assertNotChecked(T.EST_SUN_2000); // the Sunday reopen is skipped
        _assertDay(MLK_MON_0000, false, true); // the reopen is at 20:00 ET on the holiday
        _assertDay(MLK_TUE_0000, true, true);
    }

    function test_afterRead_NewYearHolidayAcrossUTCYear() public {
        oracle.setHolidayET(2025, 1, 1, true);
        _assertNotChecked(NY_TUE_2000); // ET date 2024-12-31, the next ET date is the holiday
        _assertDay(NY_WED_0000, false, true);
    }

    // ================================================================== _afterRead: windows

    function test_afterRead_OwnWindowPerTransition() public {
        oracle.setTransitionWindow(ITransitionManager.Transition.PreMarketToRegular, true, 1 hours);
        oracle.setTransitionWindow(ITransitionManager.Transition.RegularToPostMarket, true, 0);
        _assertChecked(EDT_WED_0000 + AT_0400, OVERNIGHT_TO_PRE, WINDOW);
        _assertChecked(EDT_WED_0000 + AT_0930, PRE_TO_REGULAR, 1 hours);
        _assertNotChecked(EDT_WED_0000 + AT_1600);
        _assertChecked(EDT_WED_0000 + AT_2000, POST_TO_OVERNIGHT, WINDOW);
    }

    function test_afterRead_ZeroDefaultWindowDisablesAllChecks() public {
        oracle.setDefaultTransitionWindow(0);
        _assertDay(EDT_WED_0000, false, false);
    }

    function test_afterRead_LongestWindowsDoNotOverlap() public {
        uint256 w = MAX_WINDOW - 1;
        oracle.setDefaultTransitionWindow(w);
        _assertChecked(EDT_WED_0000 + AT_0400, OVERNIGHT_TO_PRE, w);
        _assertChecked(EDT_WED_0000 + AT_0930, PRE_TO_REGULAR, w);
        _assertChecked(EDT_WED_0000 + AT_1600, REGULAR_TO_POST, w); // ends at 19:59:59, the 20:00 boundary is accepted
        _assertChecked(EDT_WED_0000 + AT_2000, POST_TO_OVERNIGHT, w); // ends at 23:59:59
        _expectOk(EDT_WED_0000 + 1 days); // Thu 00:00
    }

    // ================================================================== _afterRead: hook order and round data

    function test_RevertWhen_afterRead_PriceZeroInWindow() public {
        // The base check runs first.
        vm.warp(EDT_WED_0000 + AT_0930 + 1);
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.PriceZero.selector));
        oracle.exposed_afterRead(_round(0, block.timestamp));
    }

    function test_afterRead_IgnoresRoundData() public {
        vm.warp(EDT_WED_0000 + 12 hours);
        oracle.exposed_afterRead(_round(1, 0));
        vm.warp(EDT_WED_0000 + AT_0930 + 1);
        vm.expectRevert(abi.encodeWithSelector(ITransitionCheckerWithHolidays.TransitionPreMarketToRegular.selector));
        oracle.exposed_afterRead(_round(1, block.timestamp));
    }

    function test_checkTransition_SameResultAsAfterRead() public {
        vm.warp(EDT_WED_0000 + AT_1600 + 1);
        vm.expectRevert(abi.encodeWithSelector(ITransitionCheckerWithHolidays.TransitionRegularToPostMarket.selector));
        oracle.exposed_checkTransition();
        vm.warp(EDT_WED_0000 + 12 hours);
        oracle.exposed_checkTransition();
    }

    function test_RevertWhen_afterRead_Year9999Weekday() public {
        // The next date is in year 10000 (UnixTimestamp.getNextDate).
        _expectRevert(Y9999_FRI_NOON, UnixTimestamp.InvalidYear.selector);
    }

    function test_afterRead_Year9999Saturday() public {
        // No transition on a Saturday, so the next date is not calculated.
        _expectOk(Y9999_SAT_NOON);
    }

    // ================================================================== MarketHoliday integration

    function test_setHolidayET_InheritedFromMarketHoliday() public {
        vm.expectEmit(true, true, true, true, address(oracle));
        emit IMarketHoliday.HolidaySet(2024, 11, 28, true);
        oracle.setHolidayET(2024, 11, 28, true);
        assertTrue(oracle.exposed_checkIsHolidayET(2024, 11, 28));
    }

    function test_RevertWhen_setHolidayET_NotOwner() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        oracle.setHolidayET(2024, 11, 28, true);
    }

    // ================================================================== end-to-end through _price

    function test_price_OutsideWindow() public view {
        assertEq(oracle.exposed_price(), 400e8);
    }

    function test_RevertWhen_price_InWindow() public {
        vm.warp(EDT_WED_0000 + AT_0930 + 1);
        vm.expectRevert(abi.encodeWithSelector(ITransitionCheckerWithHolidays.TransitionPreMarketToRegular.selector));
        oracle.exposed_price();
    }

    // ================================================================== fuzz

    /// @dev Random holidays in a 4-week window and random windows. The expected result comes from a simpler model:
    ///      the 04:00, 09:30 and 16:00 ET transitions of the ET date D occur if D is a trading day, the 20:00 ET
    ///      transition occurs if D + 1 is a trading day. The model checks D and D - 1 in UTC instants, so it does not
    ///      depend on the windows ending before 00:00 ET.
    function testFuzz_afterRead_RandomHolidaysAndWindows(uint256 _week, uint256 _mask, uint256 _windows, uint256 _offset)
        public
    {
        uint256 monday = _setUpRandom(_week, _mask, _windows);
        _assertMatchesModel(monday + 7 days + bound(_offset, 0, 14 days));
    }

    /// @dev Same as above, but the timestamp is near a boundary of a random date in the window.
    function testFuzz_afterRead_RandomHolidaysAndWindows_AroundBoundary(
        uint256 _week,
        uint256 _mask,
        uint256 _windows,
        uint256 _day,
        uint8 _transition,
        uint256 _delta
    ) public {
        uint256 monday = _setUpRandom(_week, _mask, _windows);
        uint256 day = monday + (8 + bound(_day, 0, 12)) * 1 days; // UTC date in the window
        (uint256 y,,) = UnixTimestamp.getDate(day);
        uint256 boundary = ETTimestamp.toUTCTimestamp(day + _boundaryOf(uint8(bound(_transition, 0, 3))), y);
        _assertMatchesModel(boundary - 2 + bound(_delta, 0, MAX_WINDOW + 4));
    }

    function _setUpRandom(uint256 _week, uint256 _mask, uint256 _windows) internal returns (uint256 monday) {
        oracle = new TransitionCheckerWithHolidaysWrapper(address(feed), bound(_windows, 0, MAX_WINDOW - 1));
        for (uint8 i = 0; i < 4; i++) {
            uint256 seed = uint256(keccak256(abi.encode(_windows, i)));
            if (seed & 1 == 1) {
                oracle.setTransitionWindow(ITransitionManager.Transition(i), true, (seed >> 1) % MAX_WINDOW);
            }
        }
        monday = 1168214400 + bound(_week, 0, 4500) * 7 days; // Mondays from 2007-01-08
        _mask = bound(_mask, 0, (1 << 28) - 1);
        for (uint256 i = 0; i < 28; i++) {
            if ((_mask >> i) & 1 == 1 && !UnixTimestamp.isWeekendDay(monday + i * 1 days)) {
                (uint256 y, uint256 m, uint256 d) = UnixTimestamp.getDate(monday + i * 1 days);
                oracle.setHolidayET(y, m, d, true);
            }
        }
    }

    function _assertMatchesModel(uint256 _now) internal {
        bytes4 expected = _expectedError(_now);
        vm.warp(_now);
        (bool ok, bytes memory ret) =
            address(oracle).staticcall(abi.encodeCall(oracle.exposed_afterRead, (_round(1, _now))));
        if (expected == bytes4(0)) {
            assertTrue(ok, "reverted outside a window");
        } else {
            assertEq(ret, abi.encodeWithSelector(expected), "wrong result in a window");
        }
    }

    function _expectedError(uint256 _now) internal view returns (bytes4) {
        (uint256 year,,) = UnixTimestamp.getDate(_now);
        (uint256 s, uint256 e) = ETTimestamp.getETTransitionBoundariesInUTC(year);
        uint256 today = ETTimestamp.toETTimestamp(_now, s, e) / 1 days;
        for (uint256 day = today - 1; day <= today; day++) {
            (uint256 y,,) = UnixTimestamp.getDate(day * 1 days);
            for (uint8 i = 0; i < 4; i++) {
                bool occurs = i < POST_TO_OVERNIGHT ? _isTradingDay(day) : _isTradingDay(day + 1);
                if (!occurs) continue;
                uint256 boundary = ETTimestamp.toUTCTimestamp(day * 1 days + _boundaryOf(i), y);
                if (_now > boundary && _now <= boundary + _windowOf(i)) return _selector(i);
            }
        }
        return bytes4(0);
    }

    function _windowOf(uint8 _transition) internal view returns (uint256) {
        (bool isSet, uint256 window) = oracle.transitionWindows(ITransitionManager.Transition(_transition));
        return isSet ? window : oracle.defaultTransitionWindow();
    }

    function _isTradingDay(uint256 _etDayNumber) internal view returns (bool) {
        uint256 ts = _etDayNumber * 1 days;
        if (UnixTimestamp.isWeekendDay(ts)) return false;
        (uint256 y, uint256 m, uint256 d) = UnixTimestamp.getDate(ts);
        return !oracle.exposed_checkIsHolidayET(y, m, d);
    }
}
