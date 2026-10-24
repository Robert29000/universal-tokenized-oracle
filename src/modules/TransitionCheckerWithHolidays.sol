// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


import { UniversalOracleBase } from "../UniversalOracleBase.sol";
import { MarketHoliday } from "./shared/MarketHoliday.sol";
import { TransitionManager } from "./shared/TransitionManager.sol";
import { ITransitionCheckerWithHolidays } from "./interfaces/ITransitionCheckerWithHolidays.sol";

import { UnixTimestamp } from "../libraries/UnixTimestamp.sol";
import { ETTimestamp } from "../libraries/ETTimestamp.sol";
import { ETHelpers } from "../libraries/ETHelpers.sol";

/// @title TransitionCheckerWithHolidays
/// @author Robert29000
/// @notice Oracle module that rejects reads for a short time after each US market session transition. Near a
///         transition the feed can still report the price of the previous session.
///         The module skips the transitions that do not occur because of a weekend or a holiday. The holidays come
///         from `MarketHoliday`: the owner sets each holiday as an ET calendar date. The windows come from
///         `TransitionManager`.
/// @dev Overrides the `_afterRead` hook. It calls `super._afterRead(_round)` first, then `_checkTransition`. The check
///      does not read `_round`: the result depends only on `block.timestamp`, the holidays and the windows.
///      Uses the market model of `MarketHoliday`. A trading day is a weekday that is not a holiday. On the ET date D:
///      - The 04:00, 09:30 and 16:00 ET transitions are checked only if D is a trading day.
///      - The 20:00 ET transition is checked only if D + 1 is a trading day, because it is the reopen of the session
///        of D + 1. It is not checked before a weekend or a holiday, because the market closes at 20:00 ET then.
///      Each transition reverts with its own error for `boundary < ET time <= boundary + window`. The window is
///      `transitionWindows[transition].transition_window` if `is_set` is true, else `defaultTransitionWindow`.
///      Each window must be less than `MAX_TRANSITION_WINDOW`. Thus the windows do not overlap, and each window ends
///      before the next boundary and before 00:00 ET. The module compares the ET time with the boundaries of the
///      current ET date only.
///      Daylight saving time is handled with the US rules for the UTC year of `block.timestamp`
///      (see `ETHelpers.getDSTBoundaries` and `ETTimestamp`). No boundary or window is in the DST change hours
///      (01:00 to 03:00 ET), so the ET times are exact. Early closes (half days) are not handled.
///      Trust assumption: the owner sets the holidays correctly and before they occur. If a holiday is missing, the
///      module checks the transitions of that day and rejects reads in their windows. If a date is wrongly set as a
///      holiday, the module does not check its transitions.
abstract contract TransitionCheckerWithHolidays is UniversalOracleBase, TransitionManager, MarketHoliday, ITransitionCheckerWithHolidays {

    /// @notice Weekday number of Sunday in `UnixTimestamp.getWeekday` (Monday = 0).
    uint256 public constant SUNDAY = 6;

    /// @inheritdoc UniversalOracleBase
    /// @dev Calls `super._afterRead(_round)`, then `_checkTransition()`.
    function _afterRead(RoundData memory _round) internal virtual override view {
        super._afterRead(_round);

        _checkTransition();
    }

    /// @notice Reverts if `block.timestamp` is in the window of a transition that occurs on the current ET date.
    /// @dev Finds the ET date D of `block.timestamp` and its type:
    ///      - Trading day: checks the 04:00, 09:30 and 16:00 ET transitions. Checks the 20:00 ET transition if D + 1
    ///        is a trading day.
    ///      - Holiday: checks the 20:00 ET transition if D + 1 is a trading day.
    ///      - Sunday: checks the 20:00 ET transition if D + 1 (Monday) is a trading day.
    ///      - Saturday: checks no transition.
    ///      Reverts with `TransitionOvernightToPreMarket`, `TransitionPreMarketToRegular`,
    ///      `TransitionRegularToPostMarket` or `TransitionPostMarketToOvernight` (see `_isTransition`).
    ///      Reverts with `UnixTimestamp.InvalidYear` if the ET year of `block.timestamp` is 9999 or greater and D is
    ///      not a Saturday (`UnixTimestamp.getNextDate`).
    function _checkTransition() internal view {
        (uint256 dstStartTimestamp, uint256 dstEndTimestamp) = ETHelpers.getDSTBoundaries(block.timestamp);

        uint256 etTimestamp = ETTimestamp.toETTimestamp(block.timestamp, dstStartTimestamp, dstEndTimestamp);
        (uint256 year, uint256 month, uint256 day) = UnixTimestamp.getDate(etTimestamp);
        uint256 etDayTimestamp = UnixTimestamp.getTimestamp(year, month, day);

        bool isCurrentDayWeekendET = ETTimestamp.isETWeekendByDate(year, month, day);
        bool isCurrentDayHolidayET = _checkIsHolidayET(year, month, day);

        if (!(isCurrentDayWeekendET || isCurrentDayHolidayET)) {
            require(!_isTransition(Transition.OvernightToPreMarket, etTimestamp, etDayTimestamp), TransitionOvernightToPreMarket());
            require(!_isTransition(Transition.PreMarketToRegular, etTimestamp, etDayTimestamp), TransitionPreMarketToRegular());
            require(!_isTransition(Transition.RegularToPostMarket, etTimestamp, etDayTimestamp), TransitionRegularToPostMarket());

            (uint256 nextYear, uint256 nextMonth, uint256 nextDay) = UnixTimestamp.getNextDate(year, month, day);

            if (!(ETTimestamp.isETWeekendByDate(nextYear, nextMonth, nextDay) || _checkIsHolidayET(nextYear, nextMonth, nextDay))) {
                require(!_isTransition(Transition.PostMarketToOvernight, etTimestamp, etDayTimestamp), TransitionPostMarketToOvernight());
            }
        } else if (isCurrentDayHolidayET) {
            (uint256 nextYear, uint256 nextMonth, uint256 nextDay) = UnixTimestamp.getNextDate(year, month, day);

            if (!(ETTimestamp.isETWeekendByDate(nextYear, nextMonth, nextDay) || _checkIsHolidayET(nextYear, nextMonth, nextDay))) {
                require(!_isTransition(Transition.PostMarketToOvernight, etTimestamp, etDayTimestamp), TransitionPostMarketToOvernight());
            }
        } else {

            uint256 weekday = UnixTimestamp.getWeekday(etTimestamp);

            if (weekday == SUNDAY) {
                (uint256 nextYear, uint256 nextMonth, uint256 nextDay) = UnixTimestamp.getNextDate(year, month, day);

                if (!(ETTimestamp.isETWeekendByDate(nextYear, nextMonth, nextDay) || _checkIsHolidayET(nextYear, nextMonth, nextDay))) {
                    require(!_isTransition(Transition.PostMarketToOvernight, etTimestamp, etDayTimestamp), TransitionPostMarketToOvernight());
                }
            }
        }
    }
}
