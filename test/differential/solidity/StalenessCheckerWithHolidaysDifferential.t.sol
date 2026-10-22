// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IUniversalOracleBase} from "src/interfaces/IUniversalOracleBase.sol";
import {IStalenessChecker} from "src/modules/interfaces/IStalenessChecker.sol";
import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {ETTimestamp} from "src/libraries/ETTimestamp.sol";
import {StalenessCheckerWithHolidaysWrapper} from "test/mocks/wrappers/StalenessCheckerWithHolidaysWrapper.sol";
import {DifferentialBase} from "./DifferentialBase.sol";

/// @notice Differential fuzz tests: StalenessCheckerWithHolidays vs a market model built on Python
///         zoneinfo("America/New_York") (`reference.py`: is_market_closed, last_market_close, holiday_staleness_outcome).
/// @dev Each case sets random holidays in a 28-day window that starts on a Monday, then compares at one timestamp:
///      - `_isETWeekendTrading` and `_isETHolidayTrading`.
///      - `_getLastETCloseTimestampInUTC` for the ET date and day type of the timestamp (only while the market is closed).
///      - The `_afterRead` result for three prices: a random age, exactly `tradingStaleness` before the last close,
///        and one second older.
///      The reference model does not copy the contract algorithm. It finds the last trading day before the current
///      session with Python dates.
contract StalenessCheckerWithHolidaysDifferentialTest is DifferentialBase {
    uint256 internal constant MAX = 30 days;
    uint256 internal constant TRADING = 4 hours;
    uint256 internal constant WINDOW = 28; // days
    uint256 internal constant FIRST_MONDAY = 1168214400; // 2007-01-08 00:00 UTC
    uint256 internal constant LAST_WEEK = 415_000; // window ends in 9963, before the year-9999 limit

    /// @dev Mirrors the tuple returned by `ffi_reference.py holiday ...`.
    struct HolidayReference {
        bool isETWeekendTrading;
        bool isETHolidayTrading;
        bool isMarketClosed;
        uint256 etYear;
        uint256 etMonth;
        uint256 etDay;
        uint256 dayType;
        uint256 lastClose;
        uint256 outcomeAtAge;
        uint256 outcomeAtCloseEdge;
        uint256 outcomeAfterCloseEdge;
    }

    // ------------------------------------------------------------------ helpers

    function _deploy(uint256 _firstDay, uint256 _mask, uint256 _grace)
        internal
        returns (StalenessCheckerWithHolidaysWrapper o)
    {
        o = new StalenessCheckerWithHolidaysWrapper(address(1), MAX, TRADING, _grace);
        for (uint256 i = 0; i < WINDOW; i++) {
            uint256 day = _firstDay + i * 1 days;
            if ((_mask >> i) & 1 == 1 && !UnixTimestamp.isWeekendDay(day)) {
                (uint256 y, uint256 m, uint256 d) = UnixTimestamp.getDate(day);
                o.setHolidayET(y, m, d, true);
            }
        }
    }

    function _check(
        StalenessCheckerWithHolidaysWrapper _o,
        uint256 _firstDay,
        uint256 _mask,
        uint256 _ts,
        uint256 _grace,
        uint256 _age
    ) internal {
        uint256[] memory args = new uint256[](7);
        (args[0], args[1], args[2], args[3], args[4], args[5], args[6]) = (_ts, _grace, _firstDay, _mask, MAX, TRADING, _age);
        HolidayReference memory r = abi.decode(_ffi("holiday", args), (HolidayReference));

        (uint256 year,,) = UnixTimestamp.getDate(_ts);
        (uint256 s, uint256 e) = ETTimestamp.getETTransitionBoundariesInUTC(year);
        string memory at = string.concat(
            " @ ", vm.toString(_ts), " grace ", vm.toString(_grace), " window ", vm.toString(_firstDay), " mask ", vm.toString(_mask)
        );

        assertEq(_o.exposed_isETWeekendTrading(_ts, s, e, _grace), r.isETWeekendTrading, string.concat("weekend", at));
        assertEq(_o.exposed_isETHolidayTrading(_ts, s, e, _grace), r.isETHolidayTrading, string.concat("holiday", at));
        if (r.isMarketClosed) {
            assertEq(
                _o.exposed_getLastETCloseTimestampInUTC(r.etYear, r.etMonth, r.etDay, uint8(r.dayType)),
                r.lastClose,
                string.concat("lastClose", at)
            );
        }

        vm.warp(_ts);
        _assertOutcome(_o, _ts - _age, r.outcomeAtAge, string.concat("afterRead(age)", at));
        _assertOutcome(_o, r.lastClose - TRADING, r.outcomeAtCloseEdge, string.concat("afterRead(close edge)", at));
        _assertOutcome(_o, r.lastClose - TRADING - 1, r.outcomeAfterCloseEdge, string.concat("afterRead(close edge - 1)", at));
    }

    function _assertOutcome(StalenessCheckerWithHolidaysWrapper _o, uint256 _updatedAt, uint256 _expected, string memory _label)
        internal
        view
    {
        IUniversalOracleBase.RoundData memory round = IUniversalOracleBase.RoundData(1, 1, 0, _updatedAt, 1);
        (bool ok, bytes memory ret) = address(_o).staticcall(abi.encodeCall(_o.exposed_afterRead, (round)));
        if (_expected == 0) {
            assertTrue(ok, _label);
        } else {
            bytes4 err = _expected == 1
                ? IStalenessChecker.MaxStalenessReached.selector
                : IStalenessChecker.TradingStalenessReached.selector;
            assertEq(ret, abi.encodeWithSelector(err), _label);
        }
    }

    /// @dev Sparse masks (about 1 holiday in 8 days) are closer to a real calendar. Dense masks give long chains.
    function _maskFromSeed(uint256 _seed, bool _sparse) internal pure returns (uint256) {
        uint256 mask = _sparse ? _seed & (_seed >> WINDOW) & (_seed >> (2 * WINDOW)) : _seed;
        return mask & ((1 << WINDOW) - 1);
    }

    // ------------------------------------------------------------------ fuzz

    /// @dev Deploys an oracle with random holidays in the window that starts on `_firstDay`, then runs `_check`.
    function _fuzzWindow(uint256 _firstDay, uint256 _seed, bool _sparse, uint256 _ts, uint256 _grace, uint256 _age)
        internal
    {
        uint256 mask = _maskFromSeed(_seed, _sparse);
        uint256 grace = bound(_grace, 0, 4 hours - 1);
        StalenessCheckerWithHolidaysWrapper o = _deploy(_firstDay, mask, grace);
        _check(o, _firstDay, mask, _ts, grace, bound(_age, 0, MAX + 1 days));
    }

    function testFuzz_diff_RandomHolidays(
        uint256 _week,
        uint256 _seed,
        bool _sparse,
        uint256 _offset,
        uint256 _grace,
        uint256 _age
    ) public {
        uint256 firstDay = FIRST_MONDAY + bound(_week, 0, LAST_WEEK) * 7 days;
        _fuzzWindow(firstDay, _seed, _sparse, firstDay + 7 days + bound(_offset, 0, 14 days), _grace, _age);
    }

    /// @dev Within +-3h of 00:00 UTC on a random day (20:00 EDT / 19:00 EST), so close to every close, reopen and
    ///      grace period end. 2015 .. 2100.
    function testFuzz_diff_RandomHolidays_AroundCloseAndReopen(
        uint256 _week,
        uint256 _seed,
        bool _sparse,
        uint256 _day,
        int256 _delta,
        uint256 _grace,
        uint256 _age
    ) public {
        uint256 firstDay = 1420416000 + bound(_week, 0, 4430) * 7 days; // Mondays from 2015-01-05
        int256 pivot = int256(firstDay + (8 + bound(_day, 0, 13)) * 1 days);
        _fuzzWindow(firstDay, _seed, _sparse, uint256(pivot + bound(_delta, -3 hours, 3 hours)), _grace, _age);
    }

    /// @dev The window contains a DST switch of a random year, and the timestamp is within +-5 days of it.
    function testFuzz_diff_RandomHolidays_AroundDSTSwitch(
        uint256 _year,
        bool _end,
        uint256 _seed,
        bool _sparse,
        int256 _delta,
        uint256 _grace,
        uint256 _age
    ) public {
        (uint256 s, uint256 e) = ETTimestamp.getETTransitionBoundariesInUTC(bound(_year, 2007, 9998));
        uint256 pivot = _end ? e : s;
        // The switch is on a Sunday: the window starts on the Monday two weeks before it.
        uint256 firstDay = pivot - pivot % 1 days - 13 days;
        _fuzzWindow(firstDay, _seed, _sparse, uint256(int256(pivot) + bound(_delta, -5 days, 5 days)), _grace, _age);
    }

    // ------------------------------------------------------------------ real holidays

    /// @dev +-1s around the close before the holiday, the reopen on the holiday, and the end of the grace period.
    function test_diff_RealHolidays_EdgeCases() public {
        // (Monday of the window, mask, close before the holiday, reopen on the holiday)
        uint256[4][5] memory cases = [
            [uint256(1731888000), 1024, 1732755600, 1732842000], // Thanksgiving, Thu 2024-11-28 (EST)
            [uint256(1710720000), 2048, 1711670400, 1711929600], // Good Friday 2024-03-29 (EDT), reopen Sunday
            [uint256(1704672000), 128, 1705107600, 1705366800], // MLK Day, Mon 2024-01-15, close Friday
            [uint256(1734912000), 516, 1735088400, 1735174800], // Christmas, Wed 2024-12-25
            [uint256(1734912000), 516, 1735693200, 1735779600] // New Year, Wed 2025-01-01 (close in UTC 2025)
        ];
        uint32[4] memory graces = [uint32(0), 1, 30 minutes, 4 hours - 1];
        for (uint256 j = 0; j < graces.length; j++) {
            for (uint256 i = 0; i < cases.length; i++) {
                (uint256 firstDay, uint256 mask, uint256 close, uint256 reopen) =
                    (cases[i][0], cases[i][1], cases[i][2], cases[i][3]);
                StalenessCheckerWithHolidaysWrapper o = _deploy(firstDay, mask, graces[j]);
                uint256 graceEnd = reopen + graces[j]; // first second after the grace period
                uint256[7] memory times = [close - 1, close, close + 1, reopen - 1, reopen, graceEnd - 1, graceEnd];
                for (uint256 k = 0; k < times.length; k++) {
                    _check(o, firstDay, mask, times[k], graces[j], TRADING + 1);
                }
            }
        }
    }
}
