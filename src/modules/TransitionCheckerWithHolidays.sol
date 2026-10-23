// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


import { UniversalOracleBase } from "../UniversalOracleBase.sol";
import { MarketHoliday } from "./shared/MarketHoliday.sol";
import { ITransitionCheckerWithHolidays } from "./interfaces/ITransitionCheckerWithHolidays.sol";

import { UnixTimestamp } from "../libraries/UnixTimestamp.sol";
import { ETTimestamp } from "../libraries/ETTimestamp.sol";
import { ETHelpers } from "../libraries/ETHelpers.sol";

/// @title TransitionCheckerWithHolidays
/// @author Robert29000
/// @notice Oracle module that rejects reads for a short time after each US market session transition. Near a
///         transition the feed can still report the price of the previous session.
///         The module skips the transitions that do not occur because of a weekend or a holiday. The holidays come
///         from `MarketHoliday`: the owner sets each holiday as an ET calendar date.
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
abstract contract TransitionCheckerWithHolidays is UniversalOracleBase, MarketHoliday, ITransitionCheckerWithHolidays {

    /// @notice Boundary of the overnight to pre-market transition: 04:00 ET, as seconds after 00:00 ET.
    uint256 public constant OVERNIGHT_TO_PRE_MARKET_OFFSET = 4 hours;
    /// @notice Boundary of the pre-market to regular transition: 09:30 ET, as seconds after 00:00 ET.
    uint256 public constant PRE_MARKET_TO_REGULAR_OFFSET = 9 hours + 30 minutes;
    /// @notice Boundary of the regular to post-market transition: 16:00 ET, as seconds after 00:00 ET.
    uint256 public constant REGULAR_TO_POST_MARKET_OFFSET = 16 hours;
    /// @notice Boundary of the post-market to overnight transition: 20:00 ET, as seconds after 00:00 ET.
    uint256 public constant POST_MARKET_TO_OVERNIGHT_OFFSET = 20 hours;

    /// @notice Weekday number of Sunday in `UnixTimestamp.getWeekday` (Monday = 0).
    uint256 public constant SUNDAY = 6;

    /// @notice Exclusive upper bound of each transition window, in seconds. It is the shortest time between two
    ///         boundaries (16:00 ET to 20:00 ET), so the windows do not overlap, and the 20:00 ET window ends before
    ///         00:00 ET.
    uint256 public constant MAX_TRANSITION_WINDOW = 4 hours;

    /// @inheritdoc ITransitionCheckerWithHolidays
    uint256 public defaultTransitionWindow;

    /// @notice Returns the window that the owner set for a transition: `(is_set, transition_window)`.
    /// @dev If `is_set` is false, the transition uses `defaultTransitionWindow`. This NatSpec is explicit (not
    ///      inherited from the interface), because `forge doc` does not show inherited NatSpec for a mapping.
    mapping(Transition => TransitionWindow) public transitionWindows;

    /// @notice Sets the default transition window.
    /// @dev Reverts with `DefaultTransitionWindowTooLong` if `_default_transition_window >= MAX_TRANSITION_WINDOW`.
    ///      Emits `DefaultTransitionWindowSet`. All transitions use the default window until the owner calls
    ///      `setTransitionWindow`.
    /// @param _default_transition_window The default window, in seconds. Can be zero: then no transition is checked.
    constructor(uint256 _default_transition_window) {
        _setDefaultTransitionWindow(_default_transition_window);
    }

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

    /// @notice Returns true if an ET timestamp is in the window of a transition on an ET date.
    /// @dev With `boundary = _etDayTimestamp + _getTransitionOffset(_transition)`, returns true if
    ///      `boundary < _etCurrentTimestamp <= boundary + window`. The boundary itself is not in the window. The window
    ///      is the window that the owner set for `_transition`, or `defaultTransitionWindow` if it is not set.
    ///      A window of zero always returns false.
    /// @param _transition The transition.
    /// @param _etCurrentTimestamp ET timestamp in seconds (a UTC timestamp minus the ET offset, see
    ///        `ETTimestamp.toETTimestamp`).
    /// @param _etDayTimestamp ET timestamp of 00:00 ET on the date of the transition.
    /// @return True if `_etCurrentTimestamp` is in the window of the transition.
    function _isTransition(Transition _transition, uint256 _etCurrentTimestamp, uint256 _etDayTimestamp) internal view returns (bool) {
        TransitionWindow memory transitionWindow = transitionWindows[_transition];

        if (!transitionWindow.is_set) {
            transitionWindow.transition_window = defaultTransitionWindow;
        }

        uint transition_boundary = _etDayTimestamp + _getTransitionOffset(_transition);

        if (_etCurrentTimestamp > transition_boundary && _etCurrentTimestamp <= transition_boundary + transitionWindow.transition_window) {
            return true;
        }
        return false;
    }

    /// @notice Returns the boundary of a transition as seconds after 00:00 ET.
    /// @param _transition The transition.
    /// @return `OVERNIGHT_TO_PRE_MARKET_OFFSET`, `PRE_MARKET_TO_REGULAR_OFFSET`, `REGULAR_TO_POST_MARKET_OFFSET` or
    ///         `POST_MARKET_TO_OVERNIGHT_OFFSET`.
    function _getTransitionOffset(Transition _transition) internal pure returns (uint256) {
        if (_transition == Transition.OvernightToPreMarket) {
            return OVERNIGHT_TO_PRE_MARKET_OFFSET;
        } else if (_transition == Transition.PreMarketToRegular) {
            return PRE_MARKET_TO_REGULAR_OFFSET;
        } else if (_transition == Transition.RegularToPostMarket) {
            return REGULAR_TO_POST_MARKET_OFFSET;
        } else {
            return POST_MARKET_TO_OVERNIGHT_OFFSET;
        }
    }

    /// @inheritdoc ITransitionCheckerWithHolidays
    /// @dev Only the owner can call this function. Reverts with `TransitionWindowTooLong` if
    ///      `_transition_window >= MAX_TRANSITION_WINDOW`, also if `_is_set` is false. It accepts the current value
    ///      again. Emits `TransitionWindowSet`.
    function setTransitionWindow(Transition _transition, bool _is_set, uint256 _transition_window) external onlyOwner {
        require(_transition_window < MAX_TRANSITION_WINDOW, TransitionWindowTooLong());

        transitionWindows[_transition].is_set = _is_set;
        transitionWindows[_transition].transition_window = _transition_window;

        emit TransitionWindowSet(_transition, _is_set, _transition_window);
    }


    /// @inheritdoc ITransitionCheckerWithHolidays
    /// @dev Only the owner can call this function. Reverts with `TransitionWindowAlreadySet` if the value does not
    ///      change, and with `DefaultTransitionWindowTooLong` if `_default_transition_window >= MAX_TRANSITION_WINDOW`.
    ///      Emits `DefaultTransitionWindowSet`.
    function setDefaultTransitionWindow(uint256 _default_transition_window) external onlyOwner {
        require(defaultTransitionWindow != _default_transition_window, TransitionWindowAlreadySet());

        _setDefaultTransitionWindow(_default_transition_window);
    }

    /// @notice Sets the default transition window.
    /// @dev Reverts with `DefaultTransitionWindowTooLong` if `_default_transition_window >= MAX_TRANSITION_WINDOW`.
    ///      Emits `DefaultTransitionWindowSet`. Does not check the caller.
    /// @param _default_transition_window The new default window, in seconds.
    function _setDefaultTransitionWindow(uint256 _default_transition_window) internal {
        require(_default_transition_window < MAX_TRANSITION_WINDOW, DefaultTransitionWindowTooLong());

        defaultTransitionWindow = _default_transition_window;

        emit DefaultTransitionWindowSet(_default_transition_window);
    }
}
