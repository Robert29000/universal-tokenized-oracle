// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title ITransitionCheckerWithHolidays
/// @author Robert29000
/// @notice Errors of the session transition module. The transition types, the window errors, events and functions are
///         in `ITransitionManager`. The holiday errors, events and functions are in `IMarketHoliday`.
interface ITransitionCheckerWithHolidays {

    /// @notice The read is in the window after the 04:00 ET transition (overnight to pre-market).
    error TransitionOvernightToPreMarket();
    /// @notice The read is in the window after the 09:30 ET transition (pre-market to regular).
    error TransitionPreMarketToRegular();
    /// @notice The read is in the window after the 16:00 ET transition (regular to post-market).
    error TransitionRegularToPostMarket();
    /// @notice The read is in the window after the 20:00 ET transition (post-market to overnight).
    error TransitionPostMarketToOvernight();
}
