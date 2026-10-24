// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IUniversalOracleBase} from "src/interfaces/IUniversalOracleBase.sol";
import {ITransitionEMAWithHolidays} from "src/modules/interfaces/ITransitionEMAWithHolidays.sol";
import {ITransitionManager} from "src/modules/shared/interfaces/ITransitionManager.sol";
import {IMarketHoliday} from "src/modules/shared/interfaces/IMarketHoliday.sol";

import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {TransitionEMAWithHolidaysWrapper} from "test/mocks/wrappers/TransitionEMAWithHolidaysWrapper.sol";
import {MockPhaseAggregator} from "test/mocks/MockPhaseAggregator.sol";
import {TimeFixtures as T} from "test/utils/TimeFixtures.sol";

contract TransitionEMAWithHolidaysTest is Test {
    MockPhaseAggregator internal feed;
    TransitionEMAWithHolidaysWrapper internal oracle;

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

    int256 internal constant PREV = 400e8;
    int256 internal constant LATEST = 410e8;

    // ------------------------------------------------------------ expected prices (Python Decimal, 80 digits)
    // price = (LATEST * (1e18 - alpha) + PREV * alpha) / 1e18, alpha = exp(-floor((t - B) * 1e18 / W) / 1e18) * 1e18.
    // The values do not come from FixedPointMathLib.expWad.
    uint256 internal constant ALPHA_END = 367879441171442321; // exp(-1)
    uint256 internal constant PRICE_AT_1 = 40001665278; // t - B = 1, W = 600
    uint256 internal constant PRICE_AT_HALF = 40393469340; // t - B = 300, W = 600
    uint256 internal constant PRICE_AT_END = 40632120558; // t - B = W
    uint256 internal constant PRICE_AT_END_DOWN = 39367879441; // t - B = W, LATEST = 390e8

    // ------------------------------------------------------------ UTC fixtures (Python zoneinfo("America/New_York"))
    uint256 internal constant EDT_WED_0000 = 1717560000; // Wed 2024-06-05 00:00 EDT
    uint256 internal constant EDT_WED_0930 = 1717594200; // Wed 2024-06-05 09:30 EDT
    uint256 internal constant EST_WED_1600 = 1704920400; // Wed 2024-01-10 16:00 EST
    uint256 internal constant DST_START_MON_0400 = 1710144000; // Mon 2024-03-11 04:00 EDT
    uint256 internal constant DST_END_MON_0400 = 1730710800; // Mon 2024-11-04 04:00 EST
    uint256 internal constant NY_TUE_2000 = 1735693200; // Tue 2024-12-31 20:00 EST (= 2025-01-01 01:00 UTC)
    uint256 internal constant TG_THU_0930 = 1732804200; // Thu 2024-11-28 09:30 EST (Thanksgiving)
    uint256 internal constant Y9999_FRI_NOON = 253401670800; // Fri 9999-12-24 12:00 EST
    uint256 internal constant Y9999_SAT_NOON = 253401757200; // Sat 9999-12-25 12:00 EST

    // ------------------------------------------------------------ ET fixtures: 00:00 ET of a date, as an ET timestamp
    uint256 internal constant ET_EDT_WED = 1717545600; // Wed 2024-06-05
    uint256 internal constant ET_EST_WED = 1704844800; // Wed 2024-01-10
    uint256 internal constant ET_FRI = 1717718400; // Fri 2024-06-07
    uint256 internal constant ET_SAT = 1717804800; // Sat 2024-06-08
    uint256 internal constant ET_SUN = 1717891200; // Sun 2024-06-09
    uint256 internal constant ET_MON = 1717977600; // Mon 2024-06-10
    uint256 internal constant ET_TG_WED = 1732665600; // Wed 2024-11-27
    uint256 internal constant ET_TG_THU = 1732752000; // Thu 2024-11-28 (Thanksgiving)
    uint256 internal constant ET_TG_FRI = 1732838400; // Fri 2024-11-29
    uint256 internal constant ET_JUL_WED = 1719964800; // Wed 2024-07-03
    uint256 internal constant ET_JUL_THU = 1720051200; // Thu 2024-07-04 (Independence Day)
    uint256 internal constant ET_JUL_FRI = 1720137600; // Fri 2024-07-05 (also set as a holiday)
    uint256 internal constant ET_JUL_SUN = 1720310400; // Sun 2024-07-07
    uint256 internal constant ET_MLK_SUN = 1705190400; // Sun 2024-01-14
    uint256 internal constant ET_MLK_MON = 1705276800; // Mon 2024-01-15 (MLK Day)
    uint256 internal constant ET_MLK_TUE = 1705363200; // Tue 2024-01-16
    uint256 internal constant ET_Y9999_FRI_NOON = 253401652800; // Fri 9999-12-24 12:00
    uint256 internal constant ET_Y9999_SAT_NOON = 253401739200; // Sat 9999-12-25 12:00

    function setUp() public {
        vm.warp(EDT_WED_0000 + 12 hours);
        feed = new MockPhaseAggregator(8, "MSFT / USD");
        oracle = new TransitionEMAWithHolidaysWrapper(address(feed), WINDOW);
    }

    // ------------------------------------------------------------ helpers

    function _boundaryOf(uint8 _transition) internal pure returns (uint256) {
        return [AT_0400, AT_0930, AT_1600, AT_2000][_transition];
    }

    function _latestRound() internal view returns (IUniversalOracleBase.RoundData memory r) {
        (r.roundId, r.answer, r.startedAt, r.updatedAt, r.answeredInRound) = feed.latestRoundData();
    }

    /// @dev The last round before the boundary `_b` (UTC) has the answer PREV, the latest round has the answer
    ///      `_latest`. Older rounds and rounds between the boundary and the latest round have other answers, so the
    ///      search must find the correct round.
    function _setUpRounds(uint256 _b, int256 _latest) internal {
        feed.pushRound(390e8, _b - 3 hours);
        feed.pushRound(395e8, _b - 1 hours);
        feed.pushRound(PREV, _b - 1 minutes);
        feed.pushRound(420e8, _b + 1);
        feed.pushRound(_latest, _b + 2);
    }

    function _priceAt(uint256 _now) internal returns (uint256) {
        vm.warp(_now);
        return oracle.exposed_price();
    }

    function _assertNone(uint256 _et) internal view {
        (bool inTransition, uint8 transition) = oracle.exposed_getTransition(_et);
        assertFalse(inTransition, "in a transition");
        assertEq(transition, OVERNIGHT_TO_PRE, "default transition");
    }

    function _assertIs(uint256 _et, uint8 _transition) internal view {
        (bool inTransition, uint8 transition) = oracle.exposed_getTransition(_et);
        assertTrue(inTransition, "not in a transition");
        assertEq(transition, _transition, "wrong transition");
    }

    /// @dev The boundary is not in the window, `(boundary, boundary + _window]` is in the window of `_transition`,
    ///      and the first second after the window is not.
    function _assertFound(uint256 _etBoundary, uint8 _transition, uint256 _window) internal view {
        _assertNone(_etBoundary);
        _assertIs(_etBoundary + 1, _transition);
        _assertIs(_etBoundary + _window, _transition);
        _assertNone(_etBoundary + _window + 1);
    }

    function _assertNotFound(uint256 _etBoundary) internal view {
        _assertNone(_etBoundary + 1);
        _assertNone(_etBoundary + WINDOW);
    }

    /// @dev Checks the four transitions of the ET date that starts at `_etDay`.
    function _assertDay(uint256 _etDay, bool _morning, bool _evening) internal view {
        for (uint8 i = 0; i < 3; i++) {
            if (_morning) _assertFound(_etDay + _boundaryOf(i), i, WINDOW);
            else _assertNotFound(_etDay + _boundaryOf(i));
        }
        if (_evening) _assertFound(_etDay + AT_2000, POST_TO_OVERNIGHT, WINDOW);
        else _assertNotFound(_etDay + AT_2000);
    }

    /// @dev Number of `getRoundData` calls to the feed during `exposed_price()` at `_now`.
    function _countGetRoundDataCalls(uint256 _now) internal returns (uint256 calls, uint256 price) {
        vm.warp(_now);
        vm.startStateDiffRecording();
        price = oracle.exposed_price();
        Vm.AccountAccess[] memory accesses = vm.stopAndReturnStateDiff();
        for (uint256 i = 0; i < accesses.length; i++) {
            if (accesses[i].account == address(feed) && _selectorOf(accesses[i].data) == feed.getRoundData.selector) {
                calls++;
            }
        }
    }

    function _selectorOf(bytes memory _data) internal pure returns (bytes4 s) {
        if (_data.length < 4) return bytes4(0);
        assembly {
            s := mload(add(_data, 32))
        }
    }

    // ================================================================== constructor and constants

    function test_constructor_SetsDefaultWindow() public view {
        assertEq(oracle.defaultTransitionWindow(), WINDOW);
        assertEq(oracle.owner(), address(this));
        assertEq(address(oracle.aggregator()), address(feed));
    }

    function test_RevertWhen_constructor_DefaultWindowEqualsMax() public {
        vm.expectRevert(abi.encodeWithSelector(ITransitionManager.DefaultTransitionWindowTooLong.selector));
        new TransitionEMAWithHolidaysWrapper(address(feed), MAX_WINDOW);
    }

    function test_RevertWhen_constructor_AggregatorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.AggregatorZeroAddress.selector));
        new TransitionEMAWithHolidaysWrapper(address(0), WINDOW);
    }

    function test_constants() public view {
        assertEq(oracle.SUNDAY(), 6);
    }

    // ================================================================== shared modules integration
    // The window storage and setters are tested in test/modules/shared/TransitionManager.t.sol, the holiday storage
    // in test/modules/shared/MarketHoliday.t.sol.

    function test_setters_InheritedFromSharedModules() public {
        vm.expectEmit(true, true, true, true, address(oracle));
        emit ITransitionManager.TransitionWindowSet(ITransitionManager.Transition.PreMarketToRegular, true, 1 hours);
        oracle.setTransitionWindow(ITransitionManager.Transition.PreMarketToRegular, true, 1 hours);

        vm.expectEmit(true, true, true, true, address(oracle));
        emit IMarketHoliday.HolidaySet(2024, 11, 28, true);
        oracle.setHolidayET(2024, 11, 28, true);
        assertTrue(oracle.exposed_checkIsHolidayET(2024, 11, 28));
    }

    function test_RevertWhen_setters_NotOwner() public {
        address alice = makeAddr("alice");
        vm.startPrank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        oracle.setTransitionWindow(ITransitionManager.Transition.OvernightToPreMarket, true, 1 hours);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        oracle.setDefaultTransitionWindow(1 hours);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        oracle.setHolidayET(2024, 11, 28, true);
        vm.stopPrank();
    }

    // ================================================================== _getTransition: trading days

    function test_getTransition_RegularDayEDT() public view {
        _assertDay(ET_EDT_WED, true, true);
    }

    function test_getTransition_RegularDayEST() public view {
        _assertDay(ET_EST_WED, true, true);
    }

    function test_getTransition_OutsideWindows() public view {
        _assertNone(ET_EDT_WED);
        _assertNone(ET_EDT_WED + 12 hours);
        _assertNone(ET_EDT_WED + 1 days - 1);
    }

    function test_getTransition_FridayEveningNotFound() public view {
        _assertDay(ET_FRI, true, false);
    }

    function test_getTransition_SaturdayNotFound() public view {
        _assertDay(ET_SAT, false, false);
    }

    function test_getTransition_SundayReopenFound() public view {
        _assertDay(ET_SUN, false, true);
        _assertDay(ET_MON, true, true);
    }

    // ================================================================== _getTransition: holidays

    function test_getTransition_Thanksgiving() public {
        oracle.setHolidayET(2024, 11, 28, true);
        _assertDay(ET_TG_WED, true, false);
        _assertDay(ET_TG_THU, false, true);
        _assertDay(ET_TG_FRI, true, false);
    }

    function test_getTransition_HolidayNotSet() public view {
        _assertDay(ET_TG_THU, true, true);
    }

    function test_getTransition_TwoHolidaysBeforeWeekend() public {
        oracle.setHolidayET(2024, 7, 4, true);
        oracle.setHolidayET(2024, 7, 5, true);
        _assertDay(ET_JUL_WED, true, false);
        _assertDay(ET_JUL_THU, false, false);
        _assertDay(ET_JUL_FRI, false, false);
        _assertDay(ET_JUL_SUN, false, true);
    }

    function test_getTransition_MondayHoliday() public {
        oracle.setHolidayET(2024, 1, 15, true);
        _assertDay(ET_MLK_SUN, false, false); // the Sunday reopen is skipped
        _assertDay(ET_MLK_MON, false, true);
        _assertDay(ET_MLK_TUE, true, true);
    }

    // ================================================================== _getTransition: windows

    function test_getTransition_OwnWindowPerTransition() public {
        oracle.setTransitionWindow(ITransitionManager.Transition.PreMarketToRegular, true, 1 hours);
        oracle.setTransitionWindow(ITransitionManager.Transition.RegularToPostMarket, true, 0);
        _assertFound(ET_EDT_WED + AT_0400, OVERNIGHT_TO_PRE, WINDOW);
        _assertFound(ET_EDT_WED + AT_0930, PRE_TO_REGULAR, 1 hours);
        _assertNotFound(ET_EDT_WED + AT_1600);
        _assertFound(ET_EDT_WED + AT_2000, POST_TO_OVERNIGHT, WINDOW);
    }

    function test_getTransition_ZeroDefaultWindow() public {
        oracle.setDefaultTransitionWindow(0);
        _assertDay(ET_EDT_WED, false, false);
    }

    function test_getTransition_LongestWindowsDoNotOverlap() public {
        uint256 w = MAX_WINDOW - 1;
        oracle.setDefaultTransitionWindow(w);
        for (uint8 i = 0; i < 4; i++) {
            _assertFound(ET_EDT_WED + _boundaryOf(i), i, w);
        }
        _assertNone(ET_EDT_WED + 1 days);
    }

    function test_RevertWhen_getTransition_Year9999Weekday() public {
        // The next date is in year 10000 (UnixTimestamp.getNextDate).
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        oracle.exposed_getTransition(ET_Y9999_FRI_NOON);
    }

    function test_getTransition_Year9999Saturday() public view {
        _assertNone(ET_Y9999_SAT_NOON);
    }

    // ================================================================== _price: smoothing in a window

    function test_price_OutsideWindowReturnsLatest() public {
        _setUpRounds(EDT_WED_0930, LATEST);
        assertEq(_priceAt(EDT_WED_0000 + 12 hours), uint256(LATEST));
        assertEq(_priceAt(EDT_WED_0930), uint256(LATEST), "boundary");
    }

    function test_price_OutsideWindowDoesNotReadRounds() public {
        _setUpRounds(EDT_WED_0930, LATEST);
        (uint256 calls, uint256 price) = _countGetRoundDataCalls(EDT_WED_0930 + WINDOW + 1);
        assertEq(calls, 0);
        assertEq(price, uint256(LATEST));
    }

    function test_price_WeightDecreasesInWindow() public {
        feed.pushRound(PREV, EDT_WED_0930 - 1 minutes);
        feed.pushRound(LATEST, EDT_WED_0930 + 1);
        assertEq(_priceAt(EDT_WED_0930 + 1), PRICE_AT_1, "B + 1");
        assertEq(_priceAt(EDT_WED_0930 + WINDOW / 2), PRICE_AT_HALF, "B + W / 2");
        assertEq(_priceAt(EDT_WED_0930 + WINDOW), PRICE_AT_END, "B + W");
    }

    function test_price_StepAtEndOfWindow() public {
        _setUpRounds(EDT_WED_0930, LATEST);
        uint256 atEnd = _priceAt(EDT_WED_0930 + WINDOW);
        uint256 after_ = _priceAt(EDT_WED_0930 + WINDOW + 1);
        assertEq(atEnd, PRICE_AT_END);
        assertEq(after_, uint256(LATEST));
        // The step is about exp(-1) of the price change.
        assertApproxEqAbs(after_ - atEnd, uint256(LATEST - PREV) * ALPHA_END / 1e18, 1);
    }

    function test_price_PriceDecrease() public {
        _setUpRounds(EDT_WED_0930, 390e8);
        assertEq(_priceAt(EDT_WED_0930 + WINDOW), PRICE_AT_END_DOWN);
    }

    function test_price_LatestRoundBeforeBoundaryNotSmoothed() public {
        feed.pushRound(PREV, EDT_WED_0930 - 1 hours);
        feed.pushRound(LATEST, EDT_WED_0930);
        (uint256 calls, uint256 price) = _countGetRoundDataCalls(EDT_WED_0930 + 1);
        assertEq(calls, 0, "the latest round is the last round before the boundary");
        assertEq(price, uint256(LATEST));
    }

    function test_price_RoundAtBoundaryIsBeforeBoundary() public {
        feed.pushRound(395e8, EDT_WED_0930 - 1);
        feed.pushRound(PREV, EDT_WED_0930);
        feed.pushRound(420e8, EDT_WED_0930 + 1);
        feed.pushRound(LATEST, EDT_WED_0930 + 2);
        assertEq(_priceAt(EDT_WED_0930 + WINDOW), PRICE_AT_END);
    }

    function test_price_NoRoundBeforeBoundaryReturnsLatest() public {
        feed.pushRound(420e8, EDT_WED_0930 + 1);
        feed.pushRound(LATEST, EDT_WED_0930 + 2);
        assertEq(_priceAt(EDT_WED_0930 + WINDOW), uint256(LATEST));
    }

    function test_price_EachTransition() public {
        for (uint8 i = 0; i < 4; i++) {
            setUp();
            uint256 b = EDT_WED_0000 + _boundaryOf(i);
            _setUpRounds(b, LATEST);
            assertEq(_priceAt(b + WINDOW), PRICE_AT_END);
        }
    }

    function test_price_EST() public {
        _setUpRounds(EST_WED_1600, LATEST);
        assertEq(_priceAt(EST_WED_1600 + WINDOW), PRICE_AT_END);
    }

    function test_price_SundayReopenUsesFridayPrice() public {
        feed.pushRound(395e8, T.EDT_FRI_2000 - 1 hours);
        feed.pushRound(PREV, T.EDT_FRI_2000 - 1);
        feed.pushRound(LATEST, T.EDT_SUN_2000 + 1);
        assertEq(_priceAt(T.EDT_SUN_2000 + WINDOW), PRICE_AT_END);
    }

    /// @dev The round at the boundary is before the boundary, the round 1 second later is after it. If the boundary
    ///      was converted to UTC with the wrong offset, the price would not be smoothed.
    function test_price_BoundaryConversionAfterDSTSwitchesAndNewYear() public {
        uint256[3] memory boundaries = [DST_START_MON_0400, DST_END_MON_0400, NY_TUE_2000];
        for (uint256 i = 0; i < boundaries.length; i++) {
            setUp();
            feed.pushRound(PREV, boundaries[i]);
            feed.pushRound(LATEST, boundaries[i] + 1);
            assertEq(_priceAt(boundaries[i] + WINDOW), PRICE_AT_END, vm.toString(boundaries[i]));
        }
    }

    function test_price_HolidayNotSmoothed() public {
        oracle.setHolidayET(2024, 11, 28, true);
        _setUpRounds(TG_THU_0930, LATEST);
        assertEq(_priceAt(TG_THU_0930 + WINDOW), uint256(LATEST));
    }

    function test_price_OwnWindowSetsDecay() public {
        oracle.setTransitionWindow(ITransitionManager.Transition.PreMarketToRegular, true, 1 hours);
        _setUpRounds(EDT_WED_0930, LATEST);
        assertEq(_priceAt(EDT_WED_0930 + 1 hours), PRICE_AT_END);
        assertEq(_priceAt(EDT_WED_0930 + 1 hours + 1), uint256(LATEST));
    }

    function test_price_ZeroWindowNotSmoothed() public {
        oracle.setDefaultTransitionWindow(0);
        _setUpRounds(EDT_WED_0930, LATEST);
        assertEq(_priceAt(EDT_WED_0930 + 1), uint256(LATEST));
    }

    function test_RevertWhen_price_LatestAnswerZero() public {
        // The base check in _afterRead runs before _adjustAnswer.
        feed.pushRound(PREV, EDT_WED_0930 - 1 minutes);
        feed.pushRound(0, EDT_WED_0930 + 1);
        vm.warp(EDT_WED_0930 + 1);
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.PriceZero.selector));
        oracle.exposed_price();
    }

    function test_RevertWhen_price_PreviousAnswerZeroOrNegative() public {
        int256[2] memory answers = [int256(0), -5];
        for (uint256 i = 0; i < answers.length; i++) {
            setUp();
            feed.pushRound(answers[i], EDT_WED_0930 - 1 minutes);
            feed.pushRound(LATEST, EDT_WED_0930 + 1);
            vm.warp(EDT_WED_0930 + 1);
            vm.expectRevert(abi.encodeWithSelector(ITransitionEMAWithHolidays.PreviousAnswerIsZero.selector));
            oracle.exposed_price();
        }
    }

    /// @dev Known behavior: -1 is the "not found" value of the search, so a previous answer of -1 is not found and
    ///      the latest answer is returned.
    function test_price_PreviousAnswerMinusOneIsNotFound() public {
        feed.pushRound(-1, EDT_WED_0930 - 1 minutes);
        feed.pushRound(LATEST, EDT_WED_0930 + 1);
        assertEq(_priceAt(EDT_WED_0930 + 1), uint256(LATEST));
    }

    function test_RevertWhen_adjustAnswer_Year9999Weekday() public {
        vm.warp(Y9999_FRI_NOON);
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        oracle.exposed_adjustAnswer(IUniversalOracleBase.RoundData(1, LATEST, 0, Y9999_FRI_NOON, 1));
    }

    function test_adjustAnswer_Year9999Saturday() public {
        vm.warp(Y9999_SAT_NOON);
        assertEq(oracle.exposed_adjustAnswer(IUniversalOracleBase.RoundData(1, LATEST, 0, 0, 1)), uint256(LATEST));
    }

    // ================================================================== _price: phases

    /// @dev Known behavior: the previous phases are not read. The last round before the boundary is in phase 1,
    ///      so it is not found and the latest answer is returned.
    function test_price_PreviousPhaseNotRead() public {
        feed.pushRound(PREV, EDT_WED_0930 - 1 minutes);
        feed.newPhase();
        feed.pushRound(LATEST, EDT_WED_0930 + 1);
        assertEq(_priceAt(EDT_WED_0930 + WINDOW), uint256(LATEST));
    }

    function test_price_CurrentPhaseRead() public {
        feed.pushRound(390e8, EDT_WED_0930 - 1 hours);
        feed.newPhase();
        feed.pushRound(PREV, EDT_WED_0930 - 1 minutes);
        feed.pushRound(LATEST, EDT_WED_0930 + 1);
        assertEq(_priceAt(EDT_WED_0930 + WINDOW), PRICE_AT_END);
    }

    // ================================================================== _applyEMA

    function test_applyEMA_UsesWindowOfTransition() public {
        oracle.setTransitionWindow(ITransitionManager.Transition.PostMarketToOvernight, true, 1 hours);
        feed.pushRound(PREV, EDT_WED_0000 + AT_2000);
        feed.pushRound(LATEST, EDT_WED_0000 + AT_2000 + 1);
        uint256 etBoundary = ET_EDT_WED + AT_2000;
        assertEq(oracle.exposed_applyEMA(POST_TO_OVERNIGHT, _latestRound(), etBoundary + 1 hours), PRICE_AT_END);
        // With the default window of 10 minutes, alpha is exp(-1) at B + 10 minutes. _applyEMA does not check that the
        // time is in the window: at B + 1 hour alpha is exp(-6), so the price is nearer to LATEST.
        oracle.setTransitionWindow(ITransitionManager.Transition.PostMarketToOvernight, false, 0);
        assertEq(oracle.exposed_applyEMA(POST_TO_OVERNIGHT, _latestRound(), etBoundary + WINDOW), PRICE_AT_END);
        assertGt(oracle.exposed_applyEMA(POST_TO_OVERNIGHT, _latestRound(), etBoundary + 1 hours), PRICE_AT_END);
    }

    // ================================================================== _getLastPriceBeforeTransition

    function test_getLastPriceBeforeTransition_ConvertsBoundaryToUTC() public {
        uint256 etBoundary = ET_EDT_WED + AT_0930;
        feed.pushRound(PREV, EDT_WED_0930);
        feed.pushRound(LATEST, EDT_WED_0930 + 1);
        (bool found, int256 answer) = oracle.exposed_getLastPriceBeforeTransition(etBoundary, _latestRound());
        assertTrue(found);
        assertEq(answer, PREV);
    }

    function test_getLastPriceBeforeTransition_LatestRoundBeforeBoundary() public {
        feed.pushRound(LATEST, EDT_WED_0930);
        (bool found, int256 answer) = oracle.exposed_getLastPriceBeforeTransition(ET_EDT_WED + AT_0930, _latestRound());
        assertTrue(found);
        assertEq(answer, LATEST);
    }

    // ================================================================== _getLatestAnswerBelowTimestamp

    function test_getLatestAnswerBelowTimestamp_EmptyRange() public view {
        (bool found, int256 answer) = oracle.exposed_getLatestAnswerBelowTimestamp(1, 0, type(uint256).max, 1);
        assertFalse(found);
        assertEq(answer, -1);
    }

    function test_getLatestAnswerBelowTimestamp_Edges() public {
        for (uint256 i = 1; i <= 5; i++) {
            feed.pushRound(int256(i), i * 100);
        }
        (bool found, int256 answer) = oracle.exposed_getLatestAnswerBelowTimestamp(1, 5, 99, 1);
        assertFalse(found, "before the first round");
        (found, answer) = oracle.exposed_getLatestAnswerBelowTimestamp(1, 5, 100, 1);
        assertEq(answer, 1, "at the first round");
        (found, answer) = oracle.exposed_getLatestAnswerBelowTimestamp(1, 5, 299, 1);
        assertEq(answer, 2, "between rounds");
        (found, answer) = oracle.exposed_getLatestAnswerBelowTimestamp(1, 5, 500, 1);
        assertEq(answer, 5, "at the last round");
        assertTrue(found);
    }

    function test_getLatestAnswerBelowTimestamp_SearchesOnlyTheRange() public {
        for (uint256 i = 1; i <= 5; i++) {
            feed.pushRound(int256(i), i * 100);
        }
        (, int256 answer) = oracle.exposed_getLatestAnswerBelowTimestamp(2, 3, 1000, 1);
        assertEq(answer, 3);
        (bool found,) = oracle.exposed_getLatestAnswerBelowTimestamp(2, 3, 150, 1);
        assertFalse(found);
    }

    /// @dev The search reads at most ceil(log2(n + 1)) rounds. With 1000 rounds, that is 10.
    function test_price_SearchCallsAreLogarithmic() public {
        uint256 b = EDT_WED_0930;
        for (uint256 i = 0; i < 1000; i++) {
            // 700 rounds before the boundary, 300 rounds after it.
            feed.pushRound(i == 699 ? PREV : int256(300e8 + i), b - 700 + i + (i >= 700 ? 1 : 0));
        }
        feed.setRound(1, 1000, LATEST, b + 300);
        (uint256 calls, uint256 price) = _countGetRoundDataCalls(b + WINDOW);
        assertLe(calls, 10);
        assertEq(price, PRICE_AT_END);
    }

    // ================================================================== fuzz

    /// @dev The search returns the same round as a linear scan. Timestamps do not decrease and can repeat.
    function testFuzz_getLatestAnswerBelowTimestamp_MatchesLinearScan(uint256 _seed, uint256 _n, uint256 _boundary)
        public
    {
        uint256 n = bound(_n, 1, 64);
        uint256 t = 1000;
        for (uint256 i = 0; i < n; i++) {
            t += uint256(keccak256(abi.encode(_seed, i))) % 3 == 0 ? 0 : uint256(keccak256(abi.encode(_seed, i))) % 100;
            feed.pushRound(int256(i + 1), t);
        }
        uint256 boundary = bound(_boundary, 900, t + 10);

        int256 expected = -1;
        for (uint64 i = 1; i <= n; i++) {
            (, int256 answer,, uint256 updatedAt,) = feed.getRoundData(uint80((uint256(1) << 64) | i));
            if (updatedAt <= boundary) expected = answer;
        }
        (bool found, int256 result) = oracle.exposed_getLatestAnswerBelowTimestamp(1, uint64(n), boundary, 1);
        assertEq(result, expected);
        assertEq(found, expected != -1);
    }

    /// @dev In the window the price is between the previous and the latest price. Its distance from the latest price
    ///      does not increase with time.
    function testFuzz_price_BetweenPrevAndLatestAndMonotonic(
        uint256 _prev,
        uint256 _latest,
        uint256 _window,
        uint256 _delta
    ) public {
        int256 prev = int256(bound(_prev, 1, 1e30));
        int256 latest = int256(bound(_latest, 1, 1e30));
        uint256 window = bound(_window, 1, MAX_WINDOW - 1);
        uint256 delta = bound(_delta, 1, window);
        if (window != WINDOW) oracle.setDefaultTransitionWindow(window);
        feed.pushRound(prev, EDT_WED_0930 - 1);
        feed.pushRound(latest, EDT_WED_0930 + 1);

        uint256 price = _priceAt(EDT_WED_0930 + delta);
        uint256 lo = uint256(prev < latest ? prev : latest);
        uint256 hi = uint256(prev < latest ? latest : prev);
        assertGe(price, lo);
        assertLe(price, hi);

        if (delta < window) {
            uint256 next = _priceAt(EDT_WED_0930 + delta + 1);
            if (latest >= prev) assertGe(next, price);
            else assertLe(next, price);
        }
        assertEq(_priceAt(EDT_WED_0930 + window + 1), uint256(latest));
    }

    /// @dev Random holidays in a 4-week window and random windows. The expected transition comes from a simpler
    ///      model: the 04:00, 09:30 and 16:00 ET transitions of the ET date D occur if D is a trading day, the 20:00
    ///      ET transition occurs if D + 1 is a trading day.
    function testFuzz_getTransition_RandomHolidaysAndWindows(
        uint256 _week,
        uint256 _mask,
        uint256 _windows,
        uint256 _day,
        uint8 _transition,
        uint256 _delta
    ) public {
        oracle = new TransitionEMAWithHolidaysWrapper(address(feed), bound(_windows, 0, MAX_WINDOW - 1));
        for (uint8 i = 0; i < 4; i++) {
            uint256 seed = uint256(keccak256(abi.encode(_windows, i)));
            if (seed & 1 == 1) {
                oracle.setTransitionWindow(ITransitionManager.Transition(i), true, (seed >> 1) % MAX_WINDOW);
            }
        }
        uint256 monday = 1168214400 + bound(_week, 0, 4500) * 7 days; // Mondays from 2007-01-08
        _mask = bound(_mask, 0, (1 << 28) - 1);
        for (uint256 i = 0; i < 28; i++) {
            if ((_mask >> i) & 1 == 1 && !UnixTimestamp.isWeekendDay(monday + i * 1 days)) {
                (uint256 y, uint256 m, uint256 d) = UnixTimestamp.getDate(monday + i * 1 days);
                oracle.setHolidayET(y, m, d, true);
            }
        }
        uint256 etDay = monday + (8 + bound(_day, 0, 12)) * 1 days;
        uint256 et = etDay + _boundaryOf(uint8(bound(_transition, 0, 3))) - 2 + bound(_delta, 0, MAX_WINDOW + 4);

        (bool expectedIn, uint8 expected) = _expectedTransition(et);
        (bool inTransition, uint8 transition) = oracle.exposed_getTransition(et);
        assertEq(inTransition, expectedIn);
        assertEq(transition, expected);
    }

    function _expectedTransition(uint256 _et) internal view returns (bool, uint8) {
        uint256 day = _et / 1 days;
        for (uint8 i = 0; i < 4; i++) {
            bool occurs = i < POST_TO_OVERNIGHT ? _isTradingDay(day) : _isTradingDay(day + 1);
            uint256 boundary = day * 1 days + _boundaryOf(i);
            if (occurs && _et > boundary && _et <= boundary + _windowOf(i)) return (true, i);
        }
        return (false, OVERNIGHT_TO_PRE);
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
