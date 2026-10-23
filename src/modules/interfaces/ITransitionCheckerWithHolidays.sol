// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title ITransitionCheckerWithHolidays
/// @author Robert29000
/// @notice Types, errors, events and configuration functions of the session transition module. The holiday errors,
///         events and functions are in `IMarketHoliday`.
interface ITransitionCheckerWithHolidays {

    /// @notice A US market session transition. Each transition has a fixed ET time of day (its boundary).
    /// @dev - `OvernightToPreMarket`: 04:00 ET.
    ///      - `PreMarketToRegular`: 09:30 ET.
    ///      - `RegularToPostMarket`: 16:00 ET.
    ///      - `PostMarketToOvernight`: 20:00 ET. This is also the reopen of the next session.
    enum Transition {
        OvernightToPreMarket,
        PreMarketToRegular,
        RegularToPostMarket,
        PostMarketToOvernight
    }

    /// @notice The window of one transition, set by the owner.
    /// @dev If `is_set` is false, the module uses `defaultTransitionWindow` and ignores `transition_window`.
    /// @param is_set True if `transition_window` replaces the default window for this transition.
    /// @param transition_window Length of the window after the boundary, in seconds. Zero disables the check of the
    ///        transition.
    struct TransitionWindow {
        bool is_set;
        uint256 transition_window;
    }

    /// @notice The default transition window given to `setDefaultTransitionWindow` is equal to the current value.
    error TransitionWindowAlreadySet();
    /// @notice The read is in the window after the 04:00 ET transition (overnight to pre-market).
    error TransitionOvernightToPreMarket();
    /// @notice The read is in the window after the 09:30 ET transition (pre-market to regular).
    error TransitionPreMarketToRegular();
    /// @notice The read is in the window after the 16:00 ET transition (regular to post-market).
    error TransitionRegularToPostMarket();
    /// @notice The read is in the window after the 20:00 ET transition (post-market to overnight).
    error TransitionPostMarketToOvernight();
    /// @notice The window given to `setTransitionWindow` is greater than or equal to `MAX_TRANSITION_WINDOW`.
    error TransitionWindowTooLong();
    /// @notice The default window given to the constructor or to `setDefaultTransitionWindow` is greater than or equal
    ///         to `MAX_TRANSITION_WINDOW`.
    error DefaultTransitionWindowTooLong();

    /// @notice Emitted when the default transition window is set, also in the constructor.
    /// @param defaultTransitionWindow The new default window, in seconds.
    event DefaultTransitionWindowSet(uint256 indexed defaultTransitionWindow);
    /// @notice Emitted when the owner sets the window of one transition.
    /// @param transition The transition.
    /// @param is_set True if the window replaces the default window, false if the transition uses the default window.
    /// @param transition_window The window of the transition, in seconds. Not used if `is_set` is false.
    event TransitionWindowSet(Transition indexed transition, bool indexed is_set, uint256 indexed transition_window);

    /// @notice Returns the window that a transition uses if the owner did not set its own window.
    /// @return The default window, in seconds.
    function defaultTransitionWindow() external view returns (uint256);

    /// @notice Returns the window that the owner set for a transition.
    /// @param _transition The transition.
    /// @return True if the window replaces the default window.
    /// @return The window of the transition, in seconds. Not used if the first value is false.
    function transitionWindows(Transition _transition) external view returns (bool, uint256);

    /// @notice Sets the window that a transition uses if the owner did not set its own window.
    /// @param _transition_window The new default window, in seconds. Must be less than `MAX_TRANSITION_WINDOW`.
    function setDefaultTransitionWindow(uint256 _transition_window) external;

    /// @notice Sets the window of one transition, or makes the transition use the default window again.
    /// @param _transition The transition.
    /// @param _is_set True to use `_transition_window`, false to use the default window.
    /// @param _transition_window The window of the transition, in seconds. Must be less than `MAX_TRANSITION_WINDOW`.
    function setTransitionWindow(Transition _transition, bool _is_set, uint256 _transition_window) external;
}
