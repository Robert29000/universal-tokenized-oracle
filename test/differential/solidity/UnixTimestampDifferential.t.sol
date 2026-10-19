// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {UnixTimestampWrapper} from "test/mocks/wrappers/UnixTimestampWrapper.sol";
import {DifferentialBase} from "./DifferentialBase.sol";

/// @notice Differential fuzz tests: UnixTimestamp.sol vs Python datetime/calendar (via ffi_reference.py).
contract UnixTimestampDifferentialTest is DifferentialBase {
    UnixTimestampWrapper internal lib;

    uint256 internal constant MAX_DATETIME = 253402300799; // 9999-12-31 23:59:59 UTC

    // Status codes returned by ffi_reference.py `timestamp`
    uint256 internal constant OK = 0;
    uint256 internal constant INVALID_YEAR = 1;
    uint256 internal constant INVALID_MONTH = 2;
    uint256 internal constant INVALID_DAY = 3;

    function setUp() public override {
        super.setUp();
        lib = new UnixTimestampWrapper();
    }

    // ------------------------------------------------------------------ helpers

    function _checkDate(uint256 _ts) internal {
        (uint256 y, uint256 m, uint256 d, uint256 wd, bool weekend) =
            abi.decode(_ffi("date", _ts), (uint256, uint256, uint256, uint256, bool));
        (uint256 sy, uint256 sm, uint256 sd) = lib.getDate(_ts);
        assertEq(sy, y, string.concat("year @ ", vm.toString(_ts)));
        assertEq(sm, m, string.concat("month @ ", vm.toString(_ts)));
        assertEq(sd, d, string.concat("day @ ", vm.toString(_ts)));
        assertEq(lib.getWeekday(_ts), wd, string.concat("weekday @ ", vm.toString(_ts)));
        assertEq(lib.isWeekendDay(_ts), weekend, string.concat("weekend @ ", vm.toString(_ts)));
    }

    function _checkTimestamp(uint256 _y, uint256 _m, uint256 _d) internal {
        (uint256 status, uint256 expected) = abi.decode(_ffi("timestamp", _y, _m, _d), (uint256, uint256));
        if (status == INVALID_YEAR) {
            vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        } else if (status == INVALID_MONTH) {
            vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidMonth.selector));
        } else if (status == INVALID_DAY) {
            vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidDay.selector));
        }
        uint256 actual = lib.getTimestamp(_y, _m, _d);
        if (status == OK) {
            assertEq(actual, expected, "timestamp");
        }
    }

    // ------------------------------------------------------------------ getDate / getWeekday / isWeekendDay

    /// @dev Entire uint256 domain (the reference reduces by 400-year Gregorian cycles past year 9999).
    function testFuzz_diff_getDate_FullDomain(uint256 _ts) public {
        _checkDate(_ts);
    }

    /// @dev Range representable by Python datetime (1970-01-01 .. 9999-12-31 23:59:59).
    function testFuzz_diff_getDate_DatetimeRange(uint256 _ts) public {
        _checkDate(bound(_ts, 0, MAX_DATETIME));
    }

    /// @dev Realistic block timestamps (2015 .. 2200).
    function testFuzz_diff_getDate_RealisticRange(uint256 _ts) public {
        _checkDate(bound(_ts, 1420070400, 7258118400));
    }

    function test_diff_getDate_EdgeCases() public {
        uint256[24] memory cases = [
            uint256(0), // epoch
            86399, // last second of 1970-01-01
            86400,
            31535999, // 1970-12-31 23:59:59
            31536000, // 1971-01-01
            68169600, // 1972-02-29 (first leap day after epoch)
            951782400, // 2000-02-29 (400-year rule)
            951868800, // 2000-03-01
            1709164800, // 2024-02-29
            1709251199, // 2024-02-29 23:59:59
            1704067199, // 2023-12-31 23:59:59
            1704067200, // 2024-01-01
            2147483647, // 2038-01-19 (int32 max)
            4107456000, // 2100-02-28 (century, not leap)
            4107542400, // 2100-03-01
            4294967295, // 2106-02-07 (uint32 max)
            13574563200, // 2400-02-29 (leap again)
            253402214400, // 9999-12-31
            MAX_DATETIME, // 9999-12-31 23:59:59
            MAX_DATETIME + 1, // 10000-01-01
            type(uint64).max,
            type(uint128).max,
            type(uint256).max - 1,
            type(uint256).max
        ];
        for (uint256 i = 0; i < cases.length; i++) {
            _checkDate(cases[i]);
        }
    }

    // ------------------------------------------------------------------ getTimestamp

    /// @dev Valid domain plus a margin of invalid years / months / days on every side.
    function testFuzz_diff_getTimestamp_BoundedDomain(uint256 _y, uint256 _m, uint256 _d) public {
        _checkTimestamp(bound(_y, 1960, 10010), bound(_m, 0, 13), bound(_d, 0, 32));
    }

    /// @dev Only valid, existing dates.
    function testFuzz_diff_getTimestamp_ValidDates(uint256 _y, uint256 _m, uint256 _d) public {
        _checkTimestamp(bound(_y, 1970, 9999), bound(_m, 1, 12), bound(_d, 1, 28));
    }

    /// @dev Unbounded inputs (overwhelmingly invalid -> exercises the revert paths).
    function testFuzz_diff_getTimestamp_Unbounded(uint256 _y, uint256 _m, uint256 _d) public {
        _checkTimestamp(_y, _m, _d);
    }

    function test_diff_getTimestamp_EdgeCases() public {
        uint256[3][22] memory cases = [
            [uint256(1970), 1, 1],
            [uint256(1970), 12, 31],
            [uint256(1972), 2, 29],
            [uint256(2000), 2, 29],
            [uint256(2023), 12, 31],
            [uint256(2024), 1, 1],
            [uint256(2024), 2, 29],
            [uint256(2100), 2, 28],
            [uint256(2100), 3, 1],
            [uint256(2400), 2, 29],
            [uint256(9999), 12, 31],
            [uint256(1969), 12, 31], // InvalidYear
            [uint256(10000), 1, 1], // InvalidYear
            [uint256(0), 1, 1], // InvalidYear
            [uint256(2024), 0, 1], // InvalidMonth
            [uint256(2024), 13, 1], // InvalidMonth
            [uint256(2024), 1, 0], // InvalidDay
            [uint256(2024), 1, 32], // InvalidDay
            [uint256(2023), 2, 29], // InvalidDay (non-existent)
            [uint256(2100), 2, 29], // InvalidDay (non-existent)
            [uint256(2024), 2, 30], // InvalidDay (non-existent)
            [uint256(2024), 4, 31] // InvalidDay (non-existent)
        ];
        for (uint256 i = 0; i < cases.length; i++) {
            _checkTimestamp(cases[i][0], cases[i][1], cases[i][2]);
        }
    }
}
