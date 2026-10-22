// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IMarketHoliday} from "src/modules/shared/interfaces/IMarketHoliday.sol";

import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";
import {ETTimestamp} from "src/libraries/ETTimestamp.sol";
import {MarketHolidayWrapper} from "test/mocks/wrappers/MarketHolidayWrapper.sol";
import {TimeFixtures as T} from "test/utils/TimeFixtures.sol";

contract MarketHolidayTest is Test {
    MarketHolidayWrapper internal oracle;

    uint256 internal constant REOPEN = 30 minutes;

    // ------------------------------------------------------------ fixtures (Python zoneinfo("America/New_York"))
    // Thanksgiving 2024: Thursday 2024-11-28 (EST)
    uint256 internal constant TG_TUE_NOON = 1732640400; // Tue 2024-11-26 12:00 EST
    uint256 internal constant TG_WED_CLOSE = 1732755600; // Wed 2024-11-27 20:00 EST (= Thu 01:00 UTC)
    uint256 internal constant TG_THU_0000 = 1732770000; // Thu 2024-11-28 00:00 EST
    uint256 internal constant TG_THU_NOON = TG_THU_0000 + 12 hours;
    uint256 internal constant TG_THU_REOPEN = 1732842000; // Thu 2024-11-28 20:00 EST
    // New Year 2025: Wednesday 2025-01-01 (EST). The close is in UTC year 2025.
    uint256 internal constant NY_CLOSE = 1735693200; // Tue 2024-12-31 20:00 EST (= 2025-01-01 01:00 UTC)
    uint256 internal constant NY_REOPEN = 1735779600; // Wed 2025-01-01 20:00 EST
    // Independence Day 2024 (Thursday 2024-07-04), with Friday 2024-07-05 also set as a holiday (EDT)
    uint256 internal constant JUL_FRI_2000 = 1720224000; // Fri 2024-07-05 20:00 EDT

    function setUp() public {
        oracle = new MarketHolidayWrapper();
    }

    // ------------------------------------------------------------ helpers

    function _bounds2024() internal pure returns (uint256, uint256) {
        return (T.DST_START_2024, T.DST_END_2024);
    }

    // ================================================================== constructor

    function test_constructor_DeployerIsOwner() public view {
        assertEq(oracle.owner(), address(this));
    }

    // ================================================================== setHolidayET

    function test_setHolidayET_SetsAndClears() public {
        assertFalse(oracle.exposed_checkIsHolidayET(2024, 11, 28));

        vm.expectEmit(true, true, true, true, address(oracle));
        emit IMarketHoliday.HolidaySet(2024, 11, 28, true);
        oracle.setHolidayET(2024, 11, 28, true);
        assertTrue(oracle.exposed_checkIsHolidayET(2024, 11, 28));
        assertFalse(oracle.exposed_checkIsHolidayET(2024, 11, 27), "neighbour day");
        assertFalse(oracle.exposed_checkIsHolidayET(2025, 11, 28), "same day, other year");

        vm.expectEmit(true, true, true, true, address(oracle));
        emit IMarketHoliday.HolidaySet(2024, 11, 28, false);
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
            abi.encodeWithSelector(IMarketHoliday.WeekendDayCannotBeSetAsHoliday.selector);
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
                abi.encodeWithSelector(IMarketHoliday.WeekendDayCannotBeSetAsHoliday.selector)
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
}
