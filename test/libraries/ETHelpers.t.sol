// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {ETTimestamp} from "src/libraries/ETTimestamp.sol";
import {ETHelpersWrapper} from "test/mocks/wrappers/ETHelpersWrapper.sol";
import {TimeFixtures as T} from "test/utils/TimeFixtures.sol";

contract ETHelpersTest is Test {
    ETHelpersWrapper internal lib;

    function setUp() public {
        lib = new ETHelpersWrapper();
    }

    // ================================================================== getDSTBoundaries

    function test_getDSTBoundaries_UsesUTCYear() public view {
        (uint256 s, uint256 e) = lib.getDSTBoundaries(T.EDT_MON_0000);
        assertEq(s, T.DST_START_2024);
        assertEq(e, T.DST_END_2024);
        (s, e) = lib.getDSTBoundaries(T.JAN_01_2024 - 1); // 2023-12-31 23:59:59 UTC
        assertEq(s, 1678604400); // 2023-03-12 07:00 UTC
        assertEq(e, 1699164000); // 2023-11-05 06:00 UTC
    }

    function test_getDSTBoundaries_NewYearInUTCBeforeET() public view {
        // 2025-01-01 01:00 UTC is still 2024-12-31 20:00 EST: the UTC year (2025) is used.
        (uint256 s, uint256 e) = lib.getDSTBoundaries(1735693200);
        assertEq(s, T.DST_START_2025);
        assertEq(e, T.DST_END_2025);
    }

    function test_getDSTBoundaries_LastTimestampOf9999() public view {
        (uint256 s, uint256 e) = lib.getDSTBoundaries(T.MAX_DATETIME);
        assertEq(s, 253377010800); // 9999-03-14 07:00 UTC
        assertEq(e, 253397570400); // 9999-11-07 06:00 UTC
    }

    function test_RevertWhen_getDSTBoundaries_YearBeyond9999() public {
        vm.expectRevert(abi.encodeWithSelector(UnixTimestamp.InvalidYear.selector));
        lib.getDSTBoundaries(T.MAX_DATETIME + 1);
    }

    function testFuzz_getDSTBoundaries_MatchesUTCYearBoundaries(uint256 _ts) public view {
        _ts = bound(_ts, 0, T.MAX_DATETIME);
        (uint256 year,,) = UnixTimestamp.getDate(_ts);
        (uint256 expectedStart, uint256 expectedEnd) = ETTimestamp.getETTransitionBoundariesInUTC(year);
        (uint256 s, uint256 e) = lib.getDSTBoundaries(_ts);
        assertEq(s, expectedStart, "start");
        assertEq(e, expectedEnd, "end");
    }
}
