// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UniversalOracleBase} from "src/UniversalOracleBase.sol";
import {TransitionManager} from "src/modules/shared/TransitionManager.sol";
import {TransitionCheckerWithHolidays} from "src/modules/TransitionCheckerWithHolidays.sol";

/// @notice Concrete oracle composed of UniversalOracleBase + TransitionCheckerWithHolidays only.
/// @dev Also deployed by the Python differential harness (test/differential/python/), so keep the ABI stable.
///      `_isTransition` and `_getTransitionOffset` are exposed by `TransitionManagerWrapper`.
contract TransitionCheckerWithHolidaysWrapper is TransitionCheckerWithHolidays {
    constructor(address _aggregator, uint256 _defaultTransitionWindow)
        UniversalOracleBase(_aggregator)
        TransitionManager(_defaultTransitionWindow)
    {}

    function exposed_price() external view returns (uint256) {
        return _price();
    }

    function exposed_afterRead(RoundData memory _round) external view {
        _afterRead(_round);
    }

    function exposed_checkTransition() external view {
        _checkTransition();
    }

    function exposed_checkIsHolidayET(uint256 _year, uint256 _month, uint256 _day) external view returns (bool) {
        return _checkIsHolidayET(_year, _month, _day);
    }
}
