// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "../UniversalOracleBase.sol";
import {ETTimestamp} from "../libraries/ETTimestamp.sol";
import {UnixTimestamp} from "../libraries/UnixTimestamp.sol";
import {ETHelpers} from "../libraries/ETHelpers.sol";

import {IStalenessChecker} from "./interfaces/IStalenessChecker.sol";


/// @title StalenessChecker
/// @author Robert29000
/// @notice Oracle module that rejects old prices. It accepts older prices during the US market
///         weekend closure (Friday 20:00 ET to Sunday 20:00 ET), when tokenized-stock feeds do not update.
/// @dev Overrides the `_afterRead` hook. It calls `super._afterRead(_round)` first, then:
///      1. Reverts with `MaxStalenessReached` if `updatedAt + maxStaleness < block.timestamp`.
///      2. If `updatedAt + tradingStaleness < block.timestamp`, the price is accepted only if both are true:
///         - `block.timestamp` is in the weekend closure, or less than `reopenTimeWait` seconds after the
///           Sunday 20:00 ET reopen (`_isETWeekendTrading`).
///         - The price was fresh at the last Friday 20:00 ET close (`_getLastETFridayCloseTimestampInUTC`):
///           `updatedAt + tradingStaleness >= lastFridayClose`.
///         Otherwise it reverts with `TradingStalenessReached`.
///      Step 2 is in the virtual `_checkTradingStaleness` function, so derived modules can extend it.
///      Daylight saving time is handled with the US rules for the UTC year of `block.timestamp`
///      (see `ETHelpers.getDSTBoundaries` and `ETTimestamp`). US market holidays and early closes are not handled.
abstract contract StalenessChecker is UniversalOracleBase, IStalenessChecker {

    /// @dev Weekday number of Saturday in `UnixTimestamp.getWeekday` (Monday = 0).
    uint256 constant SATURDAY = 5; // Monday = 0


    /// @dev Weekly market close: Friday 20:00 ET, as seconds after Monday 00:00 ET.
    uint256 constant FRIDAY_CLOSE  = 4 days + 20 hours; // Friday 20:00
    /// @dev Weekly market reopen: Sunday 20:00 ET, as seconds after Monday 00:00 ET.
    uint256 constant SUNDAY_REOPEN = 6 days + 20 hours; // Sunday 20:00
    /// @dev Length of one week, in seconds.
    uint256 constant WEEK = 7 days;

    /// @inheritdoc IStalenessChecker
    uint256 public immutable maxStaleness;
    /// @inheritdoc IStalenessChecker
    uint256 public immutable tradingStaleness;
    /// @inheritdoc IStalenessChecker
    uint256 public immutable reopenTimeWait;

    /// @notice Sets the staleness limits. The limits cannot be changed after deployment.
    /// @dev Reverts with `MaxStalenessZero`, `TradingStalenessZero`, `MaxStalenessLessThanTradingStaleness`
    ///      or `ReopenTimeWaitGreaterThanTradingStaleness` if the values do not satisfy
    ///      `0 < _tradingStaleness <= _maxStaleness` and `_reopenTimeWait <= _tradingStaleness`.
    /// @param _maxStaleness Maximum age of the price at any time, in seconds.
    /// @param _tradingStaleness Maximum age of the price while the market trades, in seconds.
    /// @param _reopenTimeWait Grace period after the Sunday 20:00 ET reopen, in seconds. Can be zero.
    constructor(uint256 _maxStaleness, uint256 _tradingStaleness, uint256 _reopenTimeWait) {
        require(_maxStaleness > 0, MaxStalenessZero());
        require(_tradingStaleness > 0, TradingStalenessZero());
        require(_maxStaleness >= _tradingStaleness, MaxStalenessLessThanTradingStaleness());
        require(_reopenTimeWait <= _tradingStaleness, ReopenTimeWaitGreaterThanTradingStaleness());


        maxStaleness = _maxStaleness;
        tradingStaleness = _tradingStaleness;
        reopenTimeWait = _reopenTimeWait;
    }

    /// @inheritdoc UniversalOracleBase
    /// @dev Calls `super._afterRead(_round)`, then:
    ///      1. Reverts with `MaxStalenessReached` if `_round.updatedAt + maxStaleness < block.timestamp`.
    ///      2. Calls `_checkTradingStaleness(_round)` if `_round.updatedAt + tradingStaleness < block.timestamp`.
    ///      A price that is not older than `tradingStaleness` is always accepted.
    function _afterRead(RoundData memory _round) internal virtual override view {
        super._afterRead(_round);

        require(_round.updatedAt + maxStaleness >= block.timestamp, MaxStalenessReached());

        if (_round.updatedAt + tradingStaleness < block.timestamp) {
            _checkTradingStaleness(_round);
        }
    }

    /// @notice Checks if a price older than `tradingStaleness` can be accepted because the market is closed.
    /// @dev `_afterRead` calls this function only if `_round.updatedAt + tradingStaleness < block.timestamp`.
    ///      `maxStaleness` is already checked. Reverts with `TradingStalenessReached` if one of these is true:
    ///      - `block.timestamp` is not in the weekend closure, and not less than `reopenTimeWait` seconds
    ///        after the Sunday 20:00 ET reopen (`_isETWeekendTrading`).
    ///      - The price was already older than `tradingStaleness` at the last Friday 20:00 ET close:
    ///        `_round.updatedAt + tradingStaleness < lastFridayClose`.
    /// @param _round The round data returned by `aggregator.latestRoundData()`.
    function _checkTradingStaleness(RoundData memory _round) internal virtual view {
        (uint256 dstStartTimestamp, uint256 dstEndTimestamp) = ETHelpers.getDSTBoundaries(block.timestamp);

        if (!_isETWeekendTrading(block.timestamp, dstStartTimestamp, dstEndTimestamp, reopenTimeWait)) {
            revert TradingStalenessReached();
        } else {
            uint256 lastFridayCloseInUTC = _getLastETFridayCloseTimestampInUTC(block.timestamp, dstStartTimestamp, dstEndTimestamp);
            require(_round.updatedAt + tradingStaleness >= lastFridayCloseInUTC, TradingStalenessReached());
        }
    }

    /// @notice Returns true if a timestamp is in the weekend market closure (Friday 20:00 ET to Sunday 20:00 ET),
    ///         or less than `_gracePeriodOffset` seconds after the Sunday 20:00 ET reopen.
    /// @dev The closure includes the close and excludes the reopen. With `_gracePeriodOffset` zero, only the
    ///      closure is checked. The grace period can continue into Monday and later days of the week.
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @param dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @param _gracePeriodOffset Grace period after the Sunday 20:00 ET reopen, in seconds.
    /// @return True if the market is closed for the weekend, or the reopen grace period is not over, at `_timestamp`.
    function _isETWeekendTrading(uint256 _timestamp, uint256 dstStartTimestamp, uint256 dstEndTimestamp, uint256 _gracePeriodOffset) internal pure returns (bool) {
        uint256 etTimestamp = ETTimestamp.toETTimestamp(_timestamp, dstStartTimestamp, dstEndTimestamp);

        return _checkETWeekendTrading(etTimestamp, _gracePeriodOffset);
    }

    /// @notice Returns true if an ET timestamp is in the weekend closure or in the grace period after the reopen.
    /// @dev Calculates the position in the ET week (seconds after Monday 00:00 ET) and compares it with
    ///      `FRIDAY_CLOSE` and `SUNDAY_REOPEN`. If `_gracePeriod` is `WEEK - SUNDAY_REOPEN + FRIDAY_CLOSE` (the time from the
    ///      reopen to the next close) or more, the result is true for the whole week.
    /// @param _etTimestamp ET timestamp in seconds (a UTC timestamp minus the ET offset, see `ETTimestamp.toETTimestamp`).
    /// @param _gracePeriod Grace period after the Sunday 20:00 ET reopen, in seconds.
    /// @return True if the market is closed for the weekend, or the reopen grace period is not over.
    function _checkETWeekendTrading(uint256 _etTimestamp, uint256 _gracePeriod) internal pure returns (bool) {
        // Seconds elapsed since Monday 00:00 ET of the current week
        uint256 secondsIntoWeek = UnixTimestamp.getWeekday(_etTimestamp) * 1 days + _etTimestamp % 1 days;

        // Monday 00:00 – Friday 20:00: market open, unless last Sunday's grace period is still running
        if (secondsIntoWeek < FRIDAY_CLOSE) {
            uint256 sinceLastReopen = secondsIntoWeek + (WEEK - SUNDAY_REOPEN);
            return sinceLastReopen < _gracePeriod;
        }

        // Friday 20:00 – Sunday 20:00: market closed
        if (secondsIntoWeek < SUNDAY_REOPEN) {
            return true;
        }

        // Sunday 20:00 – Monday 00:00: market reopened, grace period may still be running
        uint256 sinceReopen = secondsIntoWeek - SUNDAY_REOPEN;
        return sinceReopen < _gracePeriod;
    }

    /// @notice Returns the UTC timestamp of the last Friday 20:00 ET market close at or before a timestamp.
    /// @dev Friday 20:00 ET is Saturday 00:00 UTC under EDT and Saturday 01:00 UTC under EST. The function
    ///      finds the start of the last UTC Saturday at or before `_timestamp`, applies the ET offset in force at
    ///      that instant (`ETTimestamp.adjustedUTCForETOffset`), and goes back one week if the result is after
    ///      `_timestamp`.
    ///      Reverts on underflow if `_timestamp` is before 1970-01-03 01:00 UTC (the first Friday 20:00 EST close
    ///      after the Unix epoch). This does not affect current timestamps.
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @param _dstStartTimestamp DST start of the UTC year of `_timestamp`.
    /// @param _dstEndTimestamp DST end of the UTC year of `_timestamp`.
    /// @return UTC timestamp of the most recent Friday 20:00 ET close at or before `_timestamp`.
    function _getLastETFridayCloseTimestampInUTC(uint256 _timestamp, uint256 _dstStartTimestamp, uint256 _dstEndTimestamp) internal pure returns (uint256) {
        uint256 daysSinceSaturday = (UnixTimestamp.getWeekday(_timestamp) + 7 - SATURDAY) % 7;
        uint256 saturdayUTC = _timestamp - _timestamp % 1 days - daysSinceSaturday * 1 days;

        uint256 closeUTC = ETTimestamp.adjustedUTCForETOffset(saturdayUTC, _dstStartTimestamp, _dstEndTimestamp);

        if (closeUTC > _timestamp) {
            closeUTC = ETTimestamp.adjustedUTCForETOffset(saturdayUTC - WEEK, _dstStartTimestamp, _dstEndTimestamp);
        }

        return closeUTC;
    }
}