// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {MarketHoliday} from "src/modules/shared/MarketHoliday.sol";

/// @notice Concrete MarketHoliday without an oracle. The deployer becomes the owner.
contract MarketHolidayWrapper is MarketHoliday {
    constructor() Ownable(msg.sender) {}

    function exposed_isETHolidayTrading(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd, uint256 _grace)
        external
        view
        returns (bool)
    {
        return _isETHolidayTrading(_timestamp, _dstStart, _dstEnd, _grace);
    }

    function exposed_checkIsHolidayET(uint256 _year, uint256 _month, uint256 _day) external view returns (bool) {
        return _checkIsHolidayET(_year, _month, _day);
    }

    function exposed_getHolidayKey(uint256 _year, uint256 _month, uint256 _day) external pure returns (bytes32) {
        return _getHolidayKey(_year, _month, _day);
    }
}
