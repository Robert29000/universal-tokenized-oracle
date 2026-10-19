// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UnixTimestamp} from "src/libraries/UnixTimestamp.sol";

/// @notice Exposes the internal UnixTimestamp library functions as external calls.
/// @dev Also deployed by the Python differential harness (test/differential/python/), so keep the ABI stable.
contract UnixTimestampWrapper {
    function getDate(uint256 _timestamp) external pure returns (uint256 year, uint256 month, uint256 day) {
        return UnixTimestamp.getDate(_timestamp);
    }

    function getTimestamp(uint256 _year, uint256 _month, uint256 _day) external pure returns (uint256) {
        return UnixTimestamp.getTimestamp(_year, _month, _day);
    }

    function isWeekendDay(uint256 _timestamp) external pure returns (bool) {
        return UnixTimestamp.isWeekendDay(_timestamp);
    }

    function getWeekday(uint256 _timestamp) external pure returns (uint256) {
        return UnixTimestamp.getWeekday(_timestamp);
    }
}
