// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "../UniversalOracleBase.sol";
import { TransitionManager } from "./shared/TransitionManager.sol";
import { MarketHoliday } from "./shared/MarketHoliday.sol";

import { ITransitionEMAWithHolidays } from "./interfaces/ITransitionEMAWithHolidays.sol";
import { AggregatorV2V3Interface as IAggregatorV2V3 } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";


import { ETHelpers } from "../libraries/ETHelpers.sol";
import { ETTimestamp } from "../libraries/ETTimestamp.sol";
import { UnixTimestamp } from "../libraries/UnixTimestamp.sol";
import { PhaseAggregatorHelper } from "../libraries/PhaseAggregatorHelper.sol";

import { FixedPointMathLib } from "solady/utils/FixedPointMathLib.sol";


/// @title TransitionEMAWithHolidays
/// @author Robert29000
/// @notice Oracle module that smooths the price for a short time after each US market session transition. Near a
///         transition the price can change suddenly. In the window of a transition, the module returns a weighted
///         average of the latest price and the last price before the boundary. The weight of the last price before
///         the boundary decreases exponentially with time.
///         The holidays come from `MarketHoliday`. The windows come from `TransitionManager`.
/// @dev Overrides the `_adjustAnswer` hook. It finds the transitions with the same rules as
///      `TransitionCheckerWithHolidays`. A trading day is a weekday that is not a holiday. On the ET date D:
///      - The 04:00, 09:30 and 16:00 ET transitions occur only if D is a trading day.
///      - The 20:00 ET transition occurs only if D + 1 is a trading day.
///      A transition with the boundary B and the window W is in force for `B < t <= B + W`, with `t` the ET time of
///      `block.timestamp`. In this window the module returns:
///          `price = (P_latest * (1e18 - alpha) + P_prev * alpha) / 1e18`, with `alpha = expWad(-(t - B) * 1e18 / W)`.
///      - `P_latest` is the answer of the latest round.
///      - `P_prev` is the answer of the last round with `updatedAt <= B`.
///      This is not a classic EMA. The module does not store a price and does not read the rounds in the window.
///      It uses only two prices: `P_latest` and `P_prev`. `alpha` decreases from almost 1e18 at `B + 1` to
///      `expWad(-1e18)` at `B + W`. At `B + W + 1` the window ends and the module returns `P_latest`.
///      The module finds `P_prev` with a binary search over the rounds of the current phase of `aggregator`. It does
///      not read the aggregators of the previous phases. If no round of the current phase has `updatedAt <= B`, the
///      module returns `P_latest`.
///      Outside the windows, the module calls `super._adjustAnswer(_round)`.
///      Daylight saving time is handled with the US rules for the UTC year of `block.timestamp`
///      (see `ETHelpers.getDSTBoundaries` and `ETTimestamp`).
///      Trust assumption: the aggregator is a Chainlink-compatible proxy. In each phase, the round ids start at 1 and
///      `updatedAt` does not decrease when the round id increases. The owner sets the holidays correctly and before
///      they occur.
abstract contract TransitionEMAWithHolidays is UniversalOracleBase, TransitionManager, MarketHoliday, ITransitionEMAWithHolidays {

    /// @notice Weekday number of Sunday in `UnixTimestamp.getWeekday` (Monday = 0).
    uint256 public constant SUNDAY = 6;

    /// @inheritdoc UniversalOracleBase
    /// @dev Finds the transition window that contains `block.timestamp` (`_getTransition`). In a window, returns the
    ///      smoothed price (`_applyEMA`). Outside the windows, returns `super._adjustAnswer(_round)`.
    ///      Reverts with `PreviousAnswerIsZero` if the last answer before the boundary is zero or negative.
    function _adjustAnswer(RoundData memory _round) internal virtual override view returns (uint256) {
        (uint256 dstStartTimestamp, uint256 dstEndTimestamp) = ETHelpers.getDSTBoundaries(block.timestamp);
        uint256 etTimestamp = ETTimestamp.toETTimestamp(block.timestamp, dstStartTimestamp, dstEndTimestamp);

        (bool inTransition, Transition transition) = _getTransition(etTimestamp);

        if (inTransition) {

            return _applyEMA(transition, _round, etTimestamp);
        } else {

            return super._adjustAnswer(_round);
        }
    }

    /// @notice Returns the transition whose window contains an ET timestamp, if this transition occurs on the ET date.
    /// @dev Finds the ET date D of `_etTimestamp` and its type:
    ///      - Trading day: checks the 04:00, 09:30 and 16:00 ET transitions. Checks the 20:00 ET transition if D + 1
    ///        is a trading day.
    ///      - Holiday: checks the 20:00 ET transition if D + 1 is a trading day.
    ///      - Sunday: checks the 20:00 ET transition if D + 1 (Monday) is a trading day.
    ///      - Saturday: checks no transition.
    ///      The windows do not overlap (see `TransitionManager`).
    /// @param _etTimestamp ET timestamp in seconds (a UTC timestamp minus the ET offset, see
    ///        `ETTimestamp.toETTimestamp`).
    /// @return _inTransition True if `_etTimestamp` is in the window of a transition that occurs on D.
    /// @return _transition The transition. `OvernightToPreMarket` if `_inTransition` is false.
    function _getTransition(uint256 _etTimestamp) internal view returns (bool _inTransition, Transition _transition) {
        (uint256 year, uint256 month, uint256 day) = UnixTimestamp.getDate(_etTimestamp);
        uint256 etDayTimestamp = UnixTimestamp.getTimestamp(year, month, day);

        bool isCurrentDayWeekendET = ETTimestamp.isETWeekendByDate(year, month, day);
        bool isCurrentDayHolidayET = _checkIsHolidayET(year, month, day);

        _inTransition = false;
        _transition = Transition.OvernightToPreMarket;

        if (!(isCurrentDayWeekendET || isCurrentDayHolidayET)) {
            if (_isTransition(Transition.OvernightToPreMarket, _etTimestamp, etDayTimestamp)) {
                _inTransition = true;
                _transition = Transition.OvernightToPreMarket;
            } else if (_isTransition(Transition.PreMarketToRegular, _etTimestamp, etDayTimestamp)) {
                _inTransition = true;
                _transition = Transition.PreMarketToRegular;
            } else if (_isTransition(Transition.RegularToPostMarket, _etTimestamp, etDayTimestamp)) {
                _inTransition = true;
                _transition = Transition.RegularToPostMarket;
            } else {
                (uint256 nextYear, uint256 nextMonth, uint256 nextDay) = UnixTimestamp.getNextDate(year, month, day);

                if (!(ETTimestamp.isETWeekendByDate(nextYear, nextMonth, nextDay) || _checkIsHolidayET(nextYear, nextMonth, nextDay))) {
                    if (_isTransition(Transition.PostMarketToOvernight, _etTimestamp, etDayTimestamp)) {
                        _inTransition = true;
                        _transition = Transition.PostMarketToOvernight;
                    }
                }
            }
        } else if (isCurrentDayHolidayET) {
            (uint256 nextYear, uint256 nextMonth, uint256 nextDay) = UnixTimestamp.getNextDate(year, month, day);

            if (!(ETTimestamp.isETWeekendByDate(nextYear, nextMonth, nextDay) || _checkIsHolidayET(nextYear, nextMonth, nextDay))) {
                if (_isTransition(Transition.PostMarketToOvernight, _etTimestamp, etDayTimestamp)) {
                    _inTransition = true;
                    _transition = Transition.PostMarketToOvernight;
                }
            }
        } else {

            uint256 weekday = UnixTimestamp.getWeekday(_etTimestamp);

            if (weekday == SUNDAY) {
                (uint256 nextYear, uint256 nextMonth, uint256 nextDay) = UnixTimestamp.getNextDate(year, month, day);

                if (!(ETTimestamp.isETWeekendByDate(nextYear, nextMonth, nextDay) || _checkIsHolidayET(nextYear, nextMonth, nextDay))) {
                    if (_isTransition(Transition.PostMarketToOvernight, _etTimestamp, etDayTimestamp)) {
                        _inTransition = true;
                        _transition = Transition.PostMarketToOvernight;
                    }
                }
            }
        }
    }

    /// @notice Returns the weighted average of the latest price and the last price before the boundary of a transition.
    /// @dev Call this function only if `_etTimestamp` is in the window of `_transition` (see `_getTransition`). Then
    ///      `B < _etTimestamp <= B + W` with the boundary B and the window W > 0, so the function does not divide by
    ///      zero. With `P_prev` from `_getLastPriceBeforeTransition`:
    ///      - `alpha = expWad(-(_etTimestamp - B) * 1e18 / W)`, from almost 1e18 to about 0.368e18.
    ///      - The result is `(P_latest * (1e18 - alpha) + P_prev * alpha) / 1e18`, rounded down. The two weights add up
    ///        to 1e18, so the result is between `P_prev` and `P_latest`.
    ///      If `_round.updatedAt <= B`, then `P_prev = P_latest` and the result is `P_latest`.
    ///      If no round of the current phase has `updatedAt <= B`, the result is `P_latest`.
    ///      Reverts with `PreviousAnswerIsZero` if `P_prev` is zero or negative.
    /// @param _transition The transition whose window contains `_etTimestamp`.
    /// @param _round The round data returned by `aggregator.latestRoundData()`. `_afterRead` already checked that
    ///        `_round.answer > 0`.
    /// @param _etTimestamp ET timestamp of `block.timestamp`, in seconds.
    /// @return The smoothed price, scaled by `decimals()`.
    function _applyEMA(Transition _transition, RoundData memory _round, uint256 _etTimestamp) internal view returns (uint256) {
        (uint256 year, uint256 month, uint256 day) = UnixTimestamp.getDate(_etTimestamp);
        uint256 etDayTimestamp = UnixTimestamp.getTimestamp(year, month, day);

        uint256 transitionWindow = _getTransitionWindow(_transition);
        uint256 transitionBoundary = _getTransitionBoundary(_transition, etDayTimestamp);

        (bool found, int256 prevAnswer) = _getLastPriceBeforeTransition(transitionBoundary, _round);

        if (found) {
            uint256 power_exp = (_etTimestamp - transitionBoundary) * 10**18 / transitionWindow;
            uint256 alpha = uint256(FixedPointMathLib.expWad(-int256(power_exp)));

            require(prevAnswer > 0, PreviousAnswerIsZero());
            return (uint256(_round.answer) * (10**18 - alpha) + uint256(prevAnswer) * alpha) / 10**18;
        } else {

            return uint256(_round.answer);
        }
    }

    /// @notice Returns the answer of the last round of the current phase that was updated at or before a boundary.
    /// @dev Converts `_etTransitionBoundary` to UTC (`ETTimestamp.toUTCTimestamp`). Then:
    ///      - If `_round.updatedAt <= boundary`, returns `(true, _round.answer)` and does not read the aggregator.
    ///      - Else searches the rounds 1 to the aggregator round id of `_round.roundId`, in the phase of
    ///        `_round.roundId` (`_getLatestAnswerBelowTimestamp`).
    ///      The function does not read the aggregators of the previous phases.
    /// @param _etTransitionBoundary ET timestamp of the boundary of the transition, in seconds.
    /// @param _round The round data returned by `aggregator.latestRoundData()`.
    /// @return True if a round with `updatedAt <= boundary` is found.
    /// @return The answer of this round. Not used if the first value is false.
    function _getLastPriceBeforeTransition(uint256 _etTransitionBoundary, RoundData memory _round) internal view returns (bool, int256) {
        uint256 utcTransitionBoundary = ETTimestamp.toUTCTimestamp(_etTransitionBoundary);

        if (_round.updatedAt <= utcTransitionBoundary) {
            return (true, _round.answer);
        }

        (uint16 phaseId, uint64 aggregatorRoundId) = PhaseAggregatorHelper.extractPhaseIdAndRoundId(_round.roundId);

        uint64 low = 1;
        uint64 high = aggregatorRoundId;

        (bool found, int256 result) = _getLatestAnswerBelowTimestamp(address(aggregator), low, high, utcTransitionBoundary,  phaseId);

        return (found, result);
    }

    /// @notice Returns the answer of the round with the largest aggregator round id in `[low, high]` of a phase that
    ///         was updated at or before a UTC timestamp.
    /// @dev Binary search. Each step reads `getRoundData` of the proxy round id
    ///      `PhaseAggregatorHelper.addPhaseIdToAggregatorRoundId(_phaseId, mid)`. The search is correct only if
    ///      `updatedAt` does not decrease when the round id increases in the phase.
    ///      The function uses -1 as the "not found" value of `_result`. Thus a round with the answer -1 is
    ///      not found.
    ///      `low` must be 1 or more, so that `mid - 1` does not underflow.
    /// @param _aggregator Address of the Chainlink-compatible proxy.
    /// @param low The first aggregator round id of the search, 1 or more.
    /// @param high The last aggregator round id of the search.
    /// @param _utcTransitionBoundary UTC timestamp of the boundary, in seconds.
    /// @param _phaseId The phase id of the rounds.
    /// @return _found True if a round with `updatedAt <= _utcTransitionBoundary` is found.
    /// @return _result The answer of the round, or -1 if `_found` is false.
    function _getLatestAnswerBelowTimestamp(address _aggregator, uint64 low, uint64 high, uint256 _utcTransitionBoundary, uint16 _phaseId) internal view returns (bool _found, int256 _result) {
        _found = false;
        _result = -1;  // Stores the answer of the latest element found

        while (low <= high) {
            uint64 mid = (low + high) / 2;

            uint80 midRoundId = PhaseAggregatorHelper.addPhaseIdToAggregatorRoundId(_phaseId, mid);
            RoundData memory midRound;
            (midRound.roundId, midRound.answer, midRound.startedAt, midRound.updatedAt, midRound.answeredInRound) = IAggregatorV2V3(_aggregator).getRoundData(midRoundId);

            if (midRound.updatedAt <= _utcTransitionBoundary ) {
                _result = midRound.answer;
                low = mid + 1;
            } else {
                high = mid - 1;
            }
        }

        if (_result != -1) {
            _found = true;
        }
    }
}
