// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title ITransitionEMAWithHolidays
/// @author Robert29000
/// @notice Errors of the module that smooths the price after a session transition. The transition types, the window
///         errors, events and functions are in `ITransitionManager`. The holiday errors, events and functions are in
///         `IMarketHoliday`.
interface ITransitionEMAWithHolidays {

    /// @notice The answer of the last round before the boundary of the transition is zero or negative.
    error PreviousAnswerIsZero();

}
