// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UniversalOracleBase} from "src/UniversalOracleBase.sol";
import {TransitionManager} from "src/modules/shared/TransitionManager.sol";
import {TransitionEMAWithHolidays} from "src/modules/TransitionEMAWithHolidays.sol";

/// @notice Concrete oracle composed of UniversalOracleBase + TransitionEMAWithHolidays only.
/// @dev Also deployed by the Python differential harness (test/differential/python/), so keep the ABI stable.
///      `Transition` values are passed as uint8 (OvernightToPreMarket = 0 ... PostMarketToOvernight = 3).
contract TransitionEMAWithHolidaysWrapper is TransitionEMAWithHolidays {
    constructor(address _aggregator, uint256 _defaultTransitionWindow)
        UniversalOracleBase(_aggregator)
        TransitionManager(_defaultTransitionWindow)
    {}

    function exposed_price() external view returns (uint256) {
        return _price();
    }

    function exposed_adjustAnswer(RoundData memory _round) external view returns (uint256) {
        return _adjustAnswer(_round);
    }

    function exposed_getTransition(uint256 _etTimestamp) external view returns (bool, uint8) {
        (bool inTransition, Transition transition) = _getTransition(_etTimestamp);
        return (inTransition, uint8(transition));
    }

    function exposed_applyEMA(uint8 _transition, RoundData memory _round, uint256 _etTimestamp)
        external
        view
        returns (uint256)
    {
        return _applyEMA(Transition(_transition), _round, _etTimestamp);
    }

    function exposed_getLastPriceBeforeTransition(uint256 _etTransitionBoundary, RoundData memory _round)
        external
        view
        returns (bool, int256)
    {
        return _getLastPriceBeforeTransition(_etTransitionBoundary, _round);
    }

    function exposed_getLatestAnswerBelowTimestamp(
        uint64 _low,
        uint64 _high,
        uint256 _utcTransitionBoundary,
        uint16 _phaseId
    ) external view returns (bool, int256) {
        return _getLatestAnswerBelowTimestamp(address(aggregator), _low, _high, _utcTransitionBoundary, _phaseId);
    }

    function exposed_checkIsHolidayET(uint256 _year, uint256 _month, uint256 _day) external view returns (bool) {
        return _checkIsHolidayET(_year, _month, _day);
    }
}
