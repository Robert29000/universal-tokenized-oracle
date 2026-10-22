// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title IStalenessCheckerWithHolidays
/// @author Robert29000
/// @notice Types and errors of the staleness module with US market holidays. The holiday errors, events and
///         functions are in `IMarketHoliday`.
interface IStalenessCheckerWithHolidays {

    /// @notice Type of an ET calendar day, used to find the last market close.
    /// @dev - `Regular`: a weekday that is not a holiday. The market closes at 20:00 ET.
    ///      - `Holiday`: a weekday that the owner set as a holiday. The market is closed for the full session.
    ///      - `Weekend`: a Saturday or a Sunday.
    enum DayType {
        Regular,
        Holiday,
        Weekend
    }

    /// @notice The reopen time wait given to the constructor is greater than or equal to `MAX_REOPEN_TIME_WAIT`.
    error ReopenTimeWaitGreaterThanOrEqualToMaxReopenTimeWait();
}
