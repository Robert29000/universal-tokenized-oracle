// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

library UnixTimestamp {

    error InvalidYear();
    error InvalidMonth();
    error InvalidDay();

    function getDate(uint256 _timestamp) internal pure returns (uint256 year, uint256 month, uint256 day) {
        uint256 z = _timestamp / 86400;
        uint256 z_offset = z + 719468;

        uint256 era = z_offset / 146097;
        uint256 doe = z_offset - era * 146097;

        uint256 yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;

        uint256 doy = doe - (yoe * 365 + yoe / 4 - yoe / 100);
        uint256 mp = (5 * doy + 2) / 153;

        day = doy - (mp * 153 + 2) / 5 + 1;

        month = mp < 10 ? mp + 3 : mp - 9;

        year = era * 400 + yoe;
        year += month <= 2 ? 1 : 0;
    }


    function getTimestamp(uint256 _year, uint256 _month, uint256 _day) internal pure returns (uint256) {
        require(_year >= 1970 && _year <= 9999, InvalidYear());
        require(_month >= 1 && _month <= 12, InvalidMonth());
        require(_day >= 1 && _day <= 31, InvalidDay());

        uint256 y = _year - (_month <= 2 ? 1 : 0);

        uint256 era = y / 400;
        uint256 yoe = y - era * 400;

        uint256 mp = _month > 2 ? _month - 3 : _month + 9;
        uint256 doy = (153 * mp + 2) / 5 + _day - 1;

        uint256 doe = yoe * 365 + yoe / 4 - yoe / 100 + doy;

        uint256 daysSinceEpoch = era * 146097 + doe - 719468;

        return daysSinceEpoch * 1 days;
    }

    function isWeekendDay(uint256 _timestamp) internal pure returns (bool) {
        return getWeekday(_timestamp) >= 5;
    }

    function getWeekday(uint256 _timestamp) internal pure returns (uint256) {
        return (_timestamp / 86400 + 3) % 7;
    }
}