// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ITransitionManager } from "./interfaces/ITransitionManager.sol";

/// @title TransitionManager
/// @author Robert29000
/// @notice Shared module that stores the windows of the US market session transitions. The owner sets a default
///         window and, optionally, a window for each transition. Modules that check the transitions inherit this
///         contract, so all of them read the same windows.
/// @dev Each transition has a fixed boundary as an ET time of day (`_getTransitionOffset`). The window of a
///      transition is `(boundary, boundary + window]`. The window is `transitionWindows[transition].transition_window`
///      if `is_set` is true, else `defaultTransitionWindow`.
///      Each window must be less than `MAX_TRANSITION_WINDOW`. Thus the windows do not overlap, and each window ends
///      before the next boundary and before 00:00 ET.
abstract contract TransitionManager is Ownable, ITransitionManager {

    /// @notice Boundary of the overnight to pre-market transition: 04:00 ET, as seconds after 00:00 ET.
    uint256 public constant OVERNIGHT_TO_PRE_MARKET_OFFSET = 4 hours;
    /// @notice Boundary of the pre-market to regular transition: 09:30 ET, as seconds after 00:00 ET.
    uint256 public constant PRE_MARKET_TO_REGULAR_OFFSET = 9 hours + 30 minutes;
    /// @notice Boundary of the regular to post-market transition: 16:00 ET, as seconds after 00:00 ET.
    uint256 public constant REGULAR_TO_POST_MARKET_OFFSET = 16 hours;
    /// @notice Boundary of the post-market to overnight transition: 20:00 ET, as seconds after 00:00 ET.
    uint256 public constant POST_MARKET_TO_OVERNIGHT_OFFSET = 20 hours;

    /// @notice Exclusive upper bound of each transition window, in seconds. It is the shortest time between two
    ///         boundaries (16:00 ET to 20:00 ET), so the windows do not overlap, and the 20:00 ET window ends before
    ///         00:00 ET.
    uint256 public constant MAX_TRANSITION_WINDOW = 4 hours;

    /// @inheritdoc ITransitionManager
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
        uint256 transitionWindow = _getTransitionWindow(_transition);

        uint transition_boundary = _getTransitionBoundary(_transition, _etDayTimestamp);

        if (_etCurrentTimestamp > transition_boundary && _etCurrentTimestamp <= transition_boundary + transitionWindow) {
            return true;
        }
        return false;
    }

    /// @notice Returns the window in force for a transition.
    /// @dev Returns `transitionWindows[_transition].transition_window` if `is_set` is true, else
    ///      `defaultTransitionWindow`.
    /// @param _transition The transition.
    /// @return The window, in seconds. Zero if the transition is not checked.
    function _getTransitionWindow(Transition _transition) internal view returns (uint256) {
        TransitionWindow memory transitionWindow = transitionWindows[_transition];

        if (!transitionWindow.is_set) {
            transitionWindow.transition_window = defaultTransitionWindow;
        }

        return transitionWindow.transition_window;
    }

    /// @notice Returns the boundary of a transition on an ET date, as an ET timestamp.
    /// @dev The result is `_etDayTimestamp + _getTransitionOffset(_transition)`.
    /// @param _transition The transition.
    /// @param _etDayTimestamp ET timestamp of 00:00 ET on the date of the transition.
    /// @return ET timestamp of the boundary, in seconds.
    function _getTransitionBoundary(Transition _transition, uint256 _etDayTimestamp) internal pure returns (uint256) {
        return _etDayTimestamp + _getTransitionOffset(_transition);
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

    /// @inheritdoc ITransitionManager
    /// @dev Only the owner can call this function. Reverts with `TransitionWindowTooLong` if
    ///      `_transition_window >= MAX_TRANSITION_WINDOW`, also if `_is_set` is false. It accepts the current value
    ///      again. Emits `TransitionWindowSet`.
    function setTransitionWindow(Transition _transition, bool _is_set, uint256 _transition_window) external onlyOwner {
        require(_transition_window < MAX_TRANSITION_WINDOW, TransitionWindowTooLong());

        transitionWindows[_transition].is_set = _is_set;
        transitionWindows[_transition].transition_window = _transition_window;

        emit TransitionWindowSet(_transition, _is_set, _transition_window);
    }

    /// @inheritdoc ITransitionManager
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
