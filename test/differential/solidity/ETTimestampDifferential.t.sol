// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {ETTimestampWrapper} from "test/mocks/wrappers/ETTimestampWrapper.sol";
import {StalenessCheckerWrapper} from "test/mocks/wrappers/StalenessCheckerWrapper.sol";
import {DifferentialBase} from "./DifferentialBase.sol";

/// @notice Differential fuzz tests: ETTimestamp.sol and the StalenessChecker weekend helpers vs Python
///         zoneinfo("America/New_York").
/// @dev The library hard-codes the post-2007 US DST rule, so the comparison domain starts in 2007.
///      DST boundaries are always taken from getETTransitionBoundariesInUTC(<UTC year of ts>), exactly
///      as StalenessChecker does. The weekend helpers (`_isETWeekendTrading`, `_checkETWeekendTrading`,
///      `_getLastETFridayCloseTimestampInUTC`) are internal to StalenessChecker and are called through
///      StalenessCheckerWrapper. They are pure, so the constructor arguments do not matter.
contract ETTimestampDifferentialTest is DifferentialBase {
    ETTimestampWrapper internal lib;
    StalenessCheckerWrapper internal oracle;

    uint256 internal constant FROM = 1168214400; // 2007-01-08 00:00 UTC
    uint256 internal constant TO = 253401696000; // 9999-12-25 00:00 UTC (reference needs a week of headroom)

    function setUp() public override {
        super.setUp();
        lib = new ETTimestampWrapper();
        oracle = new StalenessCheckerWrapper(address(1), 1, 1, 0);
    }

    // ------------------------------------------------------------------ helpers

    function _checkBoundaries(uint256 _year) internal {
        (uint256 s, uint256 e) = abi.decode(_ffi("dst", _year), (uint256, uint256));
        (uint256 ss, uint256 se) = lib.getETTransitionBoundariesInUTC(_year);
        assertEq(ss, s, string.concat("DST start ", vm.toString(_year)));
        assertEq(se, e, string.concat("DST end ", vm.toString(_year)));
    }

    /// @dev Mirrors the tuple returned by `ffi_reference.py et <ts> <grace>`.
    struct ETReference {
        uint256 offset;
        uint256 etTimestamp;
        bool isETWeekend;
        bool isETWeekendTrading;
        bool isETWeekendTradingWithGrace;
        uint256 lastFridayClose;
        uint256 adjustedUTC;
    }

    function _checkET(uint256 _ts, uint256 _grace) internal {
        ETReference memory r = abi.decode(_ffi("et", _ts, _grace), (ETReference));

        (uint256 year,,) = UnixTimestamp.getDate(_ts);
        (uint256 s, uint256 e) = lib.getETTransitionBoundariesInUTC(year);
        string memory at = string.concat(" @ ", vm.toString(_ts), " grace ", vm.toString(_grace));

        assertEq(lib.getETOffset(_ts, s, e), r.offset, string.concat("offset", at));
        assertEq(lib.toETTimestamp(_ts, s, e), r.etTimestamp, string.concat("toETTimestamp", at));
        assertEq(lib.isETWeekend(_ts, s, e), r.isETWeekend, string.concat("isETWeekend", at));
        assertEq(
            oracle.exposed_isETWeekendTrading(_ts, s, e, 0),
            r.isETWeekendTrading,
            string.concat("isETWeekendTrading", at)
        );
        assertEq(
            oracle.exposed_isETWeekendTrading(_ts, s, e, _grace),
            r.isETWeekendTradingWithGrace,
            string.concat("isETWeekendTrading(grace)", at)
        );
        assertEq(
            oracle.exposed_getLastETFridayCloseTimestampInUTC(_ts, s, e),
            r.lastFridayClose,
            string.concat("lastFridayClose", at)
        );
        assertEq(lib.adjustedUTCForETOffset(_ts, s, e), r.adjustedUTC, string.concat("adjustedUTC", at));
    }

    /// @dev Compares `toUTCTimestamp` with both allowed year arguments: the ET year of `_etTs` and the UTC year
    ///      of the result. Returns false, and checks nothing, in the two DST transition hours (the March hour that
    ///      does not exist and the November hour that occurs twice). The oracle converts only 20:00 ET, which is
    ///      never in these hours.
    function _checkToUTC(uint256 _etTs) internal returns (bool) {
        (bool valid, uint256 utc) = abi.decode(_ffi("et2utc", _etTs), (bool, uint256));
        if (!valid) return false;
        (uint256 etYear,,) = UnixTimestamp.getDate(_etTs);
        (uint256 utcYear,,) = UnixTimestamp.getDate(utc);
        string memory at = string.concat(" @ ET ", vm.toString(_etTs));
        assertEq(lib.toUTCTimestamp(_etTs, etYear), utc, string.concat("toUTCTimestamp(ET year)", at));
        assertEq(lib.toUTCTimestamp(_etTs, utcYear), utc, string.concat("toUTCTimestamp(UTC year)", at));
        return true;
    }

    // ------------------------------------------------------------------ DST boundaries

    function testFuzz_diff_getETTransitionBoundariesInUTC(uint256 _year) public {
        _checkBoundaries(bound(_year, 2007, 9999));
    }

    function test_diff_getETTransitionBoundariesInUTC_EdgeYears() public {
        uint16[12] memory yrs = [2007, 2015, 2020, 2024, 2025, 2026, 2027, 2038, 2100, 2400, 9998, 9999];
        for (uint256 i = 0; i < yrs.length; i++) {
            _checkBoundaries(yrs[i]);
        }
    }

    /// @notice Documented divergence: before 2007 the tz database uses the older US rules
    ///         (first Sunday of April .. last Sunday of October), which the library does not model.
    function test_diff_KnownDivergence_Pre2007Rules() public {
        (uint256 s, uint256 e) = abi.decode(_ffi("dst", 2006), (uint256, uint256));
        (uint256 ss, uint256 se) = lib.getETTransitionBoundariesInUTC(2006);
        assertEq(s, 1143961200); // 2006-04-02 07:00 UTC (zoneinfo)
        assertEq(ss, 1142146800); // 2006-03-12 07:00 UTC (library, post-2007 rule)
        assertEq(e, 1162101600); // 2006-10-29 06:00 UTC (zoneinfo)
        assertEq(se, 1162706400); // 2006-11-05 06:00 UTC (library, post-2007 rule)
    }

    // ------------------------------------------------------------------ ET conversions

    function testFuzz_diff_ETFunctions(uint256 _ts, uint256 _grace) public {
        _checkET(bound(_ts, FROM, TO), bound(_grace, 0, 1 days));
    }

    function testFuzz_diff_ETFunctions_RealisticRange(uint256 _ts, uint256 _grace) public {
        _checkET(bound(_ts, 1420070400, 4102444800), bound(_grace, 0, 6 hours)); // 2015 .. 2100
    }

    /// @dev Within +-36h of a DST switch in a random year.
    function testFuzz_diff_ETFunctions_AroundDSTSwitch(uint256 _year, int256 _delta, bool _end, uint256 _grace) public {
        _year = bound(_year, 2007, 9998);
        (uint256 s, uint256 e) = lib.getETTransitionBoundariesInUTC(_year);
        int256 delta = bound(_delta, -36 hours, 36 hours);
        uint256 pivot = _end ? e : s;
        _checkET(uint256(int256(pivot) + delta), bound(_grace, 0, 6 hours));
    }

    /// @dev Within +-3h of the Friday 20:00 close or the Sunday 20:00 reopen of a random week.
    function testFuzz_diff_ETFunctions_AroundCloseAndReopen(uint256 _week, int256 _delta, bool _sunday, uint256 _grace)
        public
    {
        // 2007-01-12 20:00 EST (a Friday close) + n weeks; offsets are re-derived by the reference anyway.
        uint256 firstClose = 1168650000;
        uint256 pivot = firstClose + bound(_week, 0, 400_000) * 7 days + (_sunday ? 2 days : 0);
        int256 delta = bound(_delta, -3 hours, 3 hours);
        _checkET(uint256(int256(pivot) + delta), bound(_grace, 0, 6 hours));
    }

    function test_diff_ETFunctions_EdgeCases() public {
        uint256[14] memory cases = [
            uint256(1710053999), // 2024-03-10 06:59:59 UTC (last EST second)
            1710054000, // 2024-03-10 07:00:00 UTC (first EDT second)
            1730613599, // 2024-11-03 05:59:59 UTC (last EDT second)
            1730613600, // 2024-11-03 06:00:00 UTC (first EST second)
            1717804799, // Fri 2024-06-07 19:59:59 EDT
            1717804800, // Fri 2024-06-07 20:00:00 EDT (close)
            1717977599, // Sun 2024-06-09 19:59:59 EDT
            1717977600, // Sun 2024-06-09 20:00:00 EDT (reopen)
            1705107599, // Fri 2024-01-12 19:59:59 EST
            1705107600, // Fri 2024-01-12 20:00:00 EST (close, Sat 01:00 UTC)
            1705105800, // Sat 2024-01-13 00:30 UTC == Fri 19:30 EST
            1704067200, // 2024-01-01 00:00 UTC (still 2023 in ET)
            1640998800, // Fri 2021-12-31 20:00 EST close (2022-01-01 01:00 UTC)
            1772953200 // 2026-03-08 07:00 UTC (Mar 1 is a Sunday)
        ];
        uint32[4] memory graces = [uint32(0), 1, 30 minutes, 5 hours];
        for (uint256 i = 0; i < cases.length; i++) {
            for (uint256 j = 0; j < graces.length; j++) {
                _checkET(cases[i], graces[j]);
            }
        }
    }

    // ------------------------------------------------------------------ ET -> UTC (toUTCTimestamp)

    function testFuzz_diff_toUTCTimestamp(uint256 _etTs) public {
        _checkToUTC(bound(_etTs, FROM, TO));
    }

    /// @dev Within +-36h (ET wall clock) of a DST switch in a random year. The transition hour itself is skipped.
    function testFuzz_diff_toUTCTimestamp_AroundDSTSwitch(uint256 _year, int256 _delta, bool _end) public {
        _year = bound(_year, 2007, 9998);
        (uint256 s, uint256 e) = lib.getETTransitionBoundariesInUTC(_year);
        // The switches happen at 02:00 ET wall clock: 07:00 UTC - 5h in March, 06:00 UTC - 4h in November.
        uint256 pivot = _end ? e - 4 hours : s - 5 hours;
        _checkToUTC(uint256(int256(pivot) + bound(_delta, -36 hours, 36 hours)));
    }

    /// @dev 20:00 ET (the market close and reopen) of any day is never in a transition hour.
    function testFuzz_diff_toUTCTimestamp_MarketClose(uint256 _day) public {
        uint256 etTs = bound(_day, FROM / 1 days, TO / 1 days) * 1 days + 20 hours;
        assertTrue(_checkToUTC(etTs), "20:00 ET was skipped");
    }

    function test_diff_toUTCTimestamp_EdgeCases() public {
        uint256 march = 1710028800; // 2024-03-10 00:00 as an ET timestamp (DST start day)
        uint256 november = 1730592000; // 2024-11-03 00:00 as an ET timestamp (DST end day)
        assertTrue(_checkToUTC(march + 2 hours - 1), "Mar 01:59:59");
        assertFalse(_checkToUTC(march + 2 hours), "Mar 02:00 does not exist");
        assertFalse(_checkToUTC(march + 3 hours - 1), "Mar 02:59:59 does not exist");
        assertTrue(_checkToUTC(march + 3 hours), "Mar 03:00");
        assertTrue(_checkToUTC(november + 1 hours - 1), "Nov 00:59:59");
        assertFalse(_checkToUTC(november + 1 hours), "Nov 01:00 occurs twice");
        assertFalse(_checkToUTC(november + 2 hours - 1), "Nov 01:59:59 occurs twice");
        assertTrue(_checkToUTC(november + 2 hours), "Nov 02:00");
        assertTrue(_checkToUTC(march + 20 hours), "Mar 20:00");
        assertTrue(_checkToUTC(november + 20 hours), "Nov 20:00");
        assertTrue(_checkToUTC(1640998800 - 5 hours), "Fri 2021-12-31 20:00 EST (UTC year 2022)");
        assertTrue(_checkToUTC(FROM), "FROM");
        assertTrue(_checkToUTC(TO), "TO");
    }
}
