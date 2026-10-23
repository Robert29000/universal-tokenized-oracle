// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UniversalOracleBase} from "src/UniversalOracleBase.sol";
import {TransitionCheckerWithHolidays} from "src/modules/TransitionCheckerWithHolidays.sol";

/// @notice Concrete oracle composed of UniversalOracleBase + TransitionCheckerWithHolidays only.
/// @dev Also deployed by the Python differential harness (test/differential/python/), so keep the ABI stable.
contract TransitionCheckerWithHolidaysWrapper is TransitionCheckerWithHolidays {
    constructor(address _aggregator, uint256 _defaultTransitionWindow)
        UniversalOracleBase(_aggregator)
        TransitionCheckerWithHolidays(_defaultTransitionWindow)
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

    /// @dev `_transition` is the `Transition` enum as uint8 (OvernightToPreMarket = 0 ... PostMarketToOvernight = 3).
    function exposed_isTransition(uint8 _transition, uint256 _etCurrentTimestamp, uint256 _etDayTimestamp)
        external
        view
        returns (bool)
    {
        return _isTransition(Transition(_transition), _etCurrentTimestamp, _etDayTimestamp);
    }

    /// @dev `_transition` is the `Transition` enum as uint8.
    function exposed_getTransitionOffset(uint8 _transition) external pure returns (uint256) {
        return _getTransitionOffset(Transition(_transition));
    }

    function exposed_checkIsHolidayET(uint256 _year, uint256 _month, uint256 _day) external view returns (bool) {
        return _checkIsHolidayET(_year, _month, _day);
    }
}
