// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UniversalOracleBase} from "src/UniversalOracleBase.sol";
import {StalenessCheckerWithHolidays} from "src/modules/StalenessCheckerWithHolidays.sol";

/// @notice Concrete oracle composed of UniversalOracleBase + StalenessCheckerWithHolidays only.
/// @dev Also deployed by the Python differential harness (test/differential/python/), so keep the ABI stable.
contract StalenessCheckerWithHolidaysWrapper is StalenessCheckerWithHolidays {
    constructor(address _aggregator, uint256 _maxStaleness, uint256 _tradingStaleness, uint256 _reopenTimeWait)
        UniversalOracleBase(_aggregator)
        StalenessCheckerWithHolidays(_maxStaleness, _tradingStaleness, _reopenTimeWait)
    {}

    function exposed_price() external view returns (uint256) {
        return _price();
    }

    function exposed_afterRead(RoundData memory _round) external view {
        _afterRead(_round);
    }

    function exposed_isETWeekendTrading(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd, uint256 _grace)
        external
        pure
        returns (bool)
    {
        return _isETWeekendTrading(_timestamp, _dstStart, _dstEnd, _grace);
    }

    function exposed_isETHolidayTrading(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd, uint256 _grace)
        external
        view
        returns (bool)
    {
        return _isETHolidayTrading(_timestamp, _dstStart, _dstEnd, _grace);
    }

    /// @dev `_dayType` is the `DayType` enum as uint8 (Regular = 0, Holiday = 1, Weekend = 2).
    function exposed_getLastETCloseTimestampInUTC(uint256 _year, uint256 _month, uint256 _day, uint8 _dayType)
        external
        view
        returns (uint256)
    {
        return _getLastETCloseTimestampInUTC(_year, _month, _day, DayType(_dayType));
    }

    function exposed_checkIsHolidayET(uint256 _year, uint256 _month, uint256 _day) external view returns (bool) {
        return _checkIsHolidayET(_year, _month, _day);
    }

    function exposed_getHolidayKey(uint256 _year, uint256 _month, uint256 _day) external pure returns (bytes32) {
        return _getHolidayKey(_year, _month, _day);
    }
}
