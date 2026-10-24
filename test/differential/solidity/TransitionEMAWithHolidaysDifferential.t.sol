// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ITransitionManager} from "src/modules/shared/interfaces/ITransitionManager.sol";
import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {ETTimestamp} from "src/libraries/ETTimestamp.sol";
import {TransitionEMAWithHolidaysWrapper} from "test/mocks/wrappers/TransitionEMAWithHolidaysWrapper.sol";
import {MockPhaseAggregator} from "test/mocks/MockPhaseAggregator.sol";
import {DifferentialBase} from "./DifferentialBase.sol";

/// @notice Differential fuzz tests: TransitionEMAWithHolidays vs a market model built on Python
///         zoneinfo("America/New_York") and an 80-digit `Decimal` exponential (`reference.py`: transition_window,
///         ema_price_range).
/// @dev Each case sets random holidays in a 28-day window that starts on a Monday, a random default window and random
///      windows for some transitions. The reference gives the transition window that contains the timestamp and the
///      UTC boundary of this window. The test then pushes random rounds before and after the boundary to a
///      `MockPhaseAggregator` and compares `_price()` with the price range of the reference.
///      The reference does not copy the contract algorithm. It finds the window with Python dates, it finds the
///      previous price with a linear scan, and it calculates the exponential with `Decimal`. solady's `expWad` is at
///      most about 1 wei from the exact value, so the reference gives the price for `alpha - 1` and `alpha + 1`.
///      The previous phases are not compared: the reference reads only the current phase, like the contract.
contract TransitionEMAWithHolidaysDifferentialTest is DifferentialBase {
    uint256 internal constant MAX_WINDOW = 4 hours;
    uint256 internal constant WINDOW = 28; // days
    uint256 internal constant FIRST_MONDAY = 1168214400; // 2007-01-08 00:00 UTC
    uint256 internal constant LAST_WEEK = 415_000; // window ends in 9963, before the year-9999 limit
    uint256 internal constant MAX_PRICE = 1e30;

    struct Case {
        TransitionEMAWithHolidaysWrapper oracle;
        MockPhaseAggregator feed;
        uint256 firstDay;
        uint256 mask;
        uint256[4] windows;
    }

    // ------------------------------------------------------------------ helpers

    function _boundaryOf(uint256 _transition) internal pure returns (uint256) {
        return [uint256(4 hours), 9 hours + 30 minutes, 16 hours, 20 hours][_transition];
    }

    /// @dev Deploys a feed and an oracle with the holidays of `_mask` and random windows from `_windowSeed`.
    function _deploy(uint256 _firstDay, uint256 _mask, uint256 _windowSeed) internal returns (Case memory c) {
        (c.firstDay, c.mask) = (_firstDay, _mask);
        c.feed = new MockPhaseAggregator(8, "MSFT / USD");
        uint256 defaultWindow = _windowSeed % MAX_WINDOW;
        c.oracle = new TransitionEMAWithHolidaysWrapper(address(c.feed), defaultWindow);
        for (uint256 i = 0; i < 4; i++) {
            uint256 seed = uint256(keccak256(abi.encode(_windowSeed, i)));
            c.windows[i] = defaultWindow;
            // About one transition in two has its own window. The own window is often short or zero.
            if (seed & 1 == 1) {
                c.windows[i] = (seed >> 1) & 1 == 1 ? (seed >> 2) % MAX_WINDOW : (seed >> 2) % 3;
                c.oracle.setTransitionWindow(ITransitionManager.Transition(i), true, c.windows[i]);
            }
        }
        for (uint256 i = 0; i < WINDOW; i++) {
            uint256 day = _firstDay + i * 1 days;
            if ((_mask >> i) & 1 == 1 && !UnixTimestamp.isWeekendDay(day)) {
                (uint256 y, uint256 m, uint256 d) = UnixTimestamp.getDate(day);
                c.oracle.setHolidayET(y, m, d, true);
            }
        }
    }

    function _transitionWindow(Case memory _c, uint256 _ts) internal returns (uint256 outcome, uint256 boundary) {
        uint256[] memory args = new uint256[](7);
        (args[0], args[1], args[2]) = (_ts, _c.firstDay, _c.mask);
        (args[3], args[4], args[5], args[6]) = (_c.windows[0], _c.windows[1], _c.windows[2], _c.windows[3]);
        (outcome, boundary) = abi.decode(_ffi("transition_window", args), (uint256, uint256));
    }

    /// @dev Pushes 0 to 5 rounds at or before `_pivot` and 0 to 3 rounds in `(_pivot, _ts]`, at least one round in
    ///      total. The last round before `_pivot` is at `_pivot`, 1 second before, or up to 1 hour before it.
    ///      Timestamps do not decrease and can repeat. Returns the rounds as (answer, updatedAt) pairs.
    function _pushRounds(Case memory _c, uint256 _pivot, uint256 _ts, uint256 _seed)
        internal
        returns (uint256[] memory flat)
    {
        uint256 nBefore = _seed % 6;
        uint256 nAfter = _pivot < _ts ? (_seed >> 8) % 4 : 0;
        if (nBefore + nAfter == 0) nBefore = 1;
        uint256 gapSel = (_seed >> 16) % 3;
        uint256 lastGap = gapSel == 0 ? 0 : gapSel == 1 ? 1 : 1 + (_seed >> 24) % 1 hours;
        uint256 step = (_seed >> 40) % 10 minutes;

        flat = new uint256[](2 * (nBefore + nAfter));
        for (uint256 k = 0; k < nBefore + nAfter; k++) {
            uint256 t = k < nBefore
                ? _pivot - lastGap - (nBefore - 1 - k) * step
                : _pivot + 1 + ((_ts - _pivot - 1) * (k - nBefore + 1)) / nAfter;
            uint256 answer = 1 + uint256(keccak256(abi.encode(_seed, k))) % MAX_PRICE;
            _c.feed.pushRound(int256(answer), t);
            (flat[2 * k], flat[2 * k + 1]) = (answer, t);
        }
    }

    function _check(Case memory _c, uint256 _ts, uint256 _roundSeed) internal {
        (uint256 outcome, uint256 boundary) = _transitionWindow(_c, _ts);
        uint256[] memory flat = _pushRounds(_c, outcome == 0 ? _ts : boundary, _ts, _roundSeed);

        uint256[] memory args = new uint256[](3 + flat.length);
        (args[0], args[1], args[2]) = (_ts, boundary, outcome == 0 ? 1 : _c.windows[outcome - 1]);
        for (uint256 i = 0; i < flat.length; i++) {
            args[3 + i] = flat[i];
        }
        (uint256 lo, uint256 hi) = abi.decode(_ffi("ema", args), (uint256, uint256));

        string memory at = string.concat(
            " @ ", vm.toString(_ts), " window ", vm.toString(_c.firstDay), " mask ", vm.toString(_c.mask),
            " rounds ", vm.toString(_roundSeed)
        );
        vm.warp(_ts);
        uint256 price = _c.oracle.exposed_price();
        assertGe(price, lo, string.concat("price below the reference", at));
        assertLe(price, hi, string.concat("price above the reference", at));
    }

    /// @dev Sparse masks (about 1 holiday in 8 days) are closer to a real calendar. Dense masks give long chains.
    function _maskFromSeed(uint256 _seed, bool _sparse) internal pure returns (uint256) {
        uint256 mask = _sparse ? _seed & (_seed >> WINDOW) & (_seed >> (2 * WINDOW)) : _seed;
        return mask & ((1 << WINDOW) - 1);
    }

    // ------------------------------------------------------------------ fuzz

    function testFuzz_diff_RandomHolidays(
        uint256 _week,
        uint256 _seed,
        bool _sparse,
        uint256 _windowSeed,
        uint256 _offset,
        uint256 _roundSeed
    ) public {
        uint256 firstDay = FIRST_MONDAY + bound(_week, 0, LAST_WEEK) * 7 days;
        Case memory c = _deploy(firstDay, _maskFromSeed(_seed, _sparse), _windowSeed);
        _check(c, firstDay + 7 days + bound(_offset, 0, 14 days), _roundSeed);
    }

    /// @dev Near a boundary of a random date: from 1 hour before the boundary in EDT to the end of the longest window
    ///      after the boundary in EST. Most cases are in a window. 2007 .. 9963.
    function testFuzz_diff_RandomHolidays_AroundBoundary(
        uint256 _week,
        uint256 _seed,
        bool _sparse,
        uint256 _windowSeed,
        uint256 _day,
        uint256 _transition,
        uint256 _delta,
        uint256 _roundSeed
    ) public {
        uint256 firstDay = FIRST_MONDAY + bound(_week, 0, LAST_WEEK) * 7 days;
        uint256 boundaryEDT = firstDay + (7 + bound(_day, 0, 13)) * 1 days + _boundaryOf(bound(_transition, 0, 3)) + 4 hours;
        uint256 ts = boundaryEDT - 1 hours + bound(_delta, 0, 2 hours + MAX_WINDOW + 1);
        Case memory c = _deploy(firstDay, _maskFromSeed(_seed, _sparse), _windowSeed);
        _check(c, ts, _roundSeed);
    }

    /// @dev The window contains a DST switch of a random year, and the timestamp is within +-5 days of it.
    function testFuzz_diff_RandomHolidays_AroundDSTSwitch(
        uint256 _year,
        bool _end,
        uint256 _seed,
        bool _sparse,
        uint256 _windowSeed,
        int256 _delta,
        uint256 _roundSeed
    ) public {
        (uint256 s, uint256 e) = ETTimestamp.getETTransitionBoundariesInUTC(bound(_year, 2007, 9998));
        uint256 pivot = _end ? e : s;
        uint256 firstDay = pivot - pivot % 1 days - 13 days;
        Case memory c = _deploy(firstDay, _maskFromSeed(_seed, _sparse), _windowSeed);
        _check(c, uint256(int256(pivot) + bound(_delta, -5 days, 5 days)), _roundSeed);
    }

    // ------------------------------------------------------------------ real holidays

    /// @dev The day before, the day of and the day after each holiday: every boundary (EDT and EST candidates) at
    ///      +1, +window / 2, +window and +window + 1 seconds. A new oracle and feed for each timestamp.
    function test_diff_RealHolidays_EdgeCases() public {
        // (Monday of the window, mask, 00:00 UTC of the holiday)
        uint256[3][3] memory cases = [
            [uint256(1731888000), 1024, 1732752000], // Thanksgiving, Thu 2024-11-28 (EST)
            [uint256(1710720000), 2048, 1711670400], // Good Friday 2024-03-29 (EDT)
            [uint256(1734912000), 516, 1735689600] // New Year, Wed 2025-01-01 (EST)
        ];
        uint256 windowSeed = 10 minutes;
        for (uint256 h = 0; h < cases.length; h++) {
            uint256[4] memory windows = _deploy(cases[h][0], cases[h][1], windowSeed).windows;
            for (uint256 day = cases[h][2] - 1 days; day <= cases[h][2] + 1 days; day += 1 days) {
                for (uint256 i = 0; i < 4; i++) {
                    for (uint256 offset = 4 hours; offset <= 5 hours; offset += 1 hours) {
                        uint256 b = day + _boundaryOf(i) + offset;
                        uint256 w = windows[i];
                        uint256[4] memory times = [b + 1, b + w / 2 + 1, b + w, b + w + 1];
                        for (uint256 k = 0; k < times.length; k++) {
                            _check(_deploy(cases[h][0], cases[h][1], windowSeed), times[k], uint256(keccak256(abi.encode(h, day, i, offset, k))));
                        }
                    }
                }
            }
        }
    }
}
