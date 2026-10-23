// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IUniversalOracleBase} from "src/interfaces/IUniversalOracleBase.sol";
import {ITransitionCheckerWithHolidays} from "src/modules/interfaces/ITransitionCheckerWithHolidays.sol";
import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {ETTimestamp} from "src/libraries/ETTimestamp.sol";
import {TransitionCheckerWithHolidaysWrapper} from "test/mocks/wrappers/TransitionCheckerWithHolidaysWrapper.sol";
import {DifferentialBase} from "./DifferentialBase.sol";

/// @notice Differential fuzz tests: TransitionCheckerWithHolidays vs a market model built on Python
///         zoneinfo("America/New_York") (`reference.py`: transition_outcome).
/// @dev Each case sets random holidays in a 28-day window that starts on a Monday, a random default window and random
///      windows for some transitions. Then it compares the `_afterRead` result at one timestamp: accepted, or the error
///      of the transition.
///      The reference model does not copy the contract algorithm. On the New York date D it finds the 04:00, 09:30 and
///      16:00 transitions if D is a trading day, and the 20:00 transition if D + 1 is a trading day. It checks D and the
///      day before, in real UTC instants.
///      The tests do not use the library under test to find a boundary. A boundary in UTC is the ET boundary plus
///      4 hours (EDT) or 5 hours (EST), so the tests cover both.
contract TransitionCheckerWithHolidaysDifferentialTest is DifferentialBase {
    uint256 internal constant MAX_WINDOW = 4 hours;
    uint256 internal constant WINDOW = 28; // days
    uint256 internal constant FIRST_MONDAY = 1168214400; // 2007-01-08 00:00 UTC
    uint256 internal constant LAST_WEEK = 415_000; // window ends in 9963, before the year-9999 limit

    // ------------------------------------------------------------------ helpers

    function _boundaryOf(uint256 _transition) internal pure returns (uint256) {
        return [uint256(4 hours), 9 hours + 30 minutes, 16 hours, 20 hours][_transition];
    }

    /// @dev Deploys an oracle with the holidays of `_mask` and random windows from `_windowSeed`. Returns the window
    ///      in force for each transition.
    function _deploy(uint256 _firstDay, uint256 _mask, uint256 _windowSeed)
        internal
        returns (TransitionCheckerWithHolidaysWrapper o, uint256[4] memory windows)
    {
        uint256 defaultWindow = _windowSeed % MAX_WINDOW;
        o = new TransitionCheckerWithHolidaysWrapper(address(1), defaultWindow);
        for (uint256 i = 0; i < 4; i++) {
            uint256 seed = uint256(keccak256(abi.encode(_windowSeed, i)));
            windows[i] = defaultWindow;
            // About one transition in two has its own window. The own window is often short or zero.
            if (seed & 1 == 1) {
                windows[i] = (seed >> 1) & 1 == 1 ? (seed >> 2) % MAX_WINDOW : (seed >> 2) % 3;
                o.setTransitionWindow(ITransitionCheckerWithHolidays.Transition(i), true, windows[i]);
            }
        }
        for (uint256 i = 0; i < WINDOW; i++) {
            uint256 day = _firstDay + i * 1 days;
            if ((_mask >> i) & 1 == 1 && !UnixTimestamp.isWeekendDay(day)) {
                (uint256 y, uint256 m, uint256 d) = UnixTimestamp.getDate(day);
                o.setHolidayET(y, m, d, true);
            }
        }
    }

    function _check(
        TransitionCheckerWithHolidaysWrapper _o,
        uint256 _firstDay,
        uint256 _mask,
        uint256[4] memory _windows,
        uint256 _ts
    ) internal {
        uint256[] memory args = new uint256[](7);
        (args[0], args[1], args[2]) = (_ts, _firstDay, _mask);
        (args[3], args[4], args[5], args[6]) = (_windows[0], _windows[1], _windows[2], _windows[3]);
        uint256 expected = abi.decode(_ffi("transition", args), (uint256));

        string memory at = string.concat(
            " @ ", vm.toString(_ts), " window ", vm.toString(_firstDay), " mask ", vm.toString(_mask)
        );

        vm.warp(_ts);
        IUniversalOracleBase.RoundData memory round = IUniversalOracleBase.RoundData(1, 1, 0, _ts, 1);
        (bool ok, bytes memory ret) = address(_o).staticcall(abi.encodeCall(_o.exposed_afterRead, (round)));
        if (expected == 0) {
            assertTrue(ok, string.concat("afterRead reverted", at));
        } else {
            assertEq(ret, abi.encodeWithSelector(_selector(expected - 1)), string.concat("afterRead", at));
        }
    }

    function _selector(uint256 _transition) internal pure returns (bytes4) {
        if (_transition == 0) return ITransitionCheckerWithHolidays.TransitionOvernightToPreMarket.selector;
        if (_transition == 1) return ITransitionCheckerWithHolidays.TransitionPreMarketToRegular.selector;
        if (_transition == 2) return ITransitionCheckerWithHolidays.TransitionRegularToPostMarket.selector;
        return ITransitionCheckerWithHolidays.TransitionPostMarketToOvernight.selector;
    }

    /// @dev Sparse masks (about 1 holiday in 8 days) are closer to a real calendar. Dense masks give long chains.
    function _maskFromSeed(uint256 _seed, bool _sparse) internal pure returns (uint256) {
        uint256 mask = _sparse ? _seed & (_seed >> WINDOW) & (_seed >> (2 * WINDOW)) : _seed;
        return mask & ((1 << WINDOW) - 1);
    }

    function _fuzzWindow(uint256 _firstDay, uint256 _seed, bool _sparse, uint256 _windowSeed, uint256 _ts) internal {
        uint256 mask = _maskFromSeed(_seed, _sparse);
        (TransitionCheckerWithHolidaysWrapper o, uint256[4] memory windows) = _deploy(_firstDay, mask, _windowSeed);
        _check(o, _firstDay, mask, windows, _ts);
    }

    // ------------------------------------------------------------------ fuzz

    function testFuzz_diff_RandomHolidays(uint256 _week, uint256 _seed, bool _sparse, uint256 _windowSeed, uint256 _offset)
        public
    {
        uint256 firstDay = FIRST_MONDAY + bound(_week, 0, LAST_WEEK) * 7 days;
        _fuzzWindow(firstDay, _seed, _sparse, _windowSeed, firstDay + 7 days + bound(_offset, 0, 14 days));
    }

    /// @dev Near a boundary of a random date: from 1 hour before the boundary in EDT to the end of the longest window
    ///      after the boundary in EST. 2007 .. 9963.
    function testFuzz_diff_RandomHolidays_AroundBoundary(
        uint256 _week,
        uint256 _seed,
        bool _sparse,
        uint256 _windowSeed,
        uint256 _day,
        uint256 _transition,
        uint256 _delta
    ) public {
        uint256 firstDay = FIRST_MONDAY + bound(_week, 0, LAST_WEEK) * 7 days;
        uint256 boundaryEDT = firstDay + (7 + bound(_day, 0, 13)) * 1 days + _boundaryOf(bound(_transition, 0, 3)) + 4 hours;
        uint256 ts = boundaryEDT - 1 hours + bound(_delta, 0, 2 hours + MAX_WINDOW + 1);
        _fuzzWindow(firstDay, _seed, _sparse, _windowSeed, ts);
    }

    /// @dev The window contains a DST switch of a random year, and the timestamp is within +-5 days of it.
    function testFuzz_diff_RandomHolidays_AroundDSTSwitch(
        uint256 _year,
        bool _end,
        uint256 _seed,
        bool _sparse,
        uint256 _windowSeed,
        int256 _delta
    ) public {
        (uint256 s, uint256 e) = ETTimestamp.getETTransitionBoundariesInUTC(bound(_year, 2007, 9998));
        uint256 pivot = _end ? e : s;
        // The switch is on a Sunday: the window starts on the Monday two weeks before it.
        uint256 firstDay = pivot - pivot % 1 days - 13 days;
        _fuzzWindow(firstDay, _seed, _sparse, _windowSeed, uint256(int256(pivot) + bound(_delta, -5 days, 5 days)));
    }

    // ------------------------------------------------------------------ real holidays

    /// @dev The day before, the day of and the day after each holiday: every boundary (EDT and EST candidates) at
    ///      +0, +1, +window and +window + 1 seconds.
    function test_diff_RealHolidays_EdgeCases() public {
        // (Monday of the window, mask, 00:00 UTC of the holiday)
        uint256[3][5] memory cases = [
            [uint256(1731888000), 1024, 1732752000], // Thanksgiving, Thu 2024-11-28 (EST)
            [uint256(1710720000), 2048, 1711670400], // Good Friday 2024-03-29 (EDT)
            [uint256(1704672000), 128, 1705276800], // MLK Day, Mon 2024-01-15 (EST)
            [uint256(1734912000), 516, 1735084800], // Christmas, Wed 2024-12-25 (EST)
            [uint256(1734912000), 516, 1735689600] // New Year, Wed 2025-01-01 (EST)
        ];
        uint256 windowSeed = 10 minutes; // default window 10 minutes; some transitions get their own window
        for (uint256 c = 0; c < cases.length; c++) {
            (TransitionCheckerWithHolidaysWrapper o, uint256[4] memory windows) =
                _deploy(cases[c][0], cases[c][1], windowSeed);
            for (uint256 day = cases[c][2] - 1 days; day <= cases[c][2] + 1 days; day += 1 days) {
                for (uint256 i = 0; i < 4; i++) {
                    for (uint256 offset = 4 hours; offset <= 5 hours; offset += 1 hours) {
                        uint256 boundary = day + _boundaryOf(i) + offset;
                        uint256[4] memory times = [boundary, boundary + 1, boundary + windows[i], boundary + windows[i] + 1];
                        for (uint256 k = 0; k < times.length; k++) {
                            _check(o, cases[c][0], cases[c][1], windows, times[k]);
                        }
                    }
                }
            }
        }
    }
}
