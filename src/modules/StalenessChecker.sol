// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "../UniversalOracleBase.sol";
import {ETTimestamp} from "../libraries/ETTimestamp.sol";
import {UnixTimestamp} from "../libraries/UnixTimestamp.sol";

import {IStalenessChecker} from "./interfaces/IStalenessChecker.sol";


/// @title StalenessChecker
/// @author Robert29000
/// @notice Oracle module that rejects old prices. It accepts older prices during the US market
///         weekend closure (Friday 20:00 ET to Sunday 20:00 ET), when tokenized-stock feeds do not update.
/// @dev Overrides the `_afterRead` hook. It calls `super._afterRead(_round)` first, then:
///      1. Reverts with `MaxStalenessReached` if `updatedAt + maxStaleness < block.timestamp`.
///      2. If `updatedAt + tradingStaleness < block.timestamp`, the price is accepted only if both are true:
///         - `block.timestamp` is in the weekend closure, or less than `reopenTimeWait` seconds after the
///           Sunday 20:00 ET reopen (`ETTimestamp.isETWeekendTrading`).
///         - The price was fresh at the last Friday 20:00 ET close:
///           `updatedAt + tradingStaleness >= lastFridayClose`.
///         Otherwise it reverts with `TradingStalenessReached`.
///      Daylight saving time is handled with the US rules for the UTC year of `block.timestamp`
///      (see `ETTimestamp`).
abstract contract StalenessChecker is UniversalOracleBase, IStalenessChecker {

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
    /// @dev Calls `super._afterRead(_round)`, then applies the `maxStaleness` and `tradingStaleness`
    ///      checks on `_round.updatedAt`. A price older than `tradingStaleness` is still accepted during the
    ///      weekend closure and for `reopenTimeWait` seconds after the Sunday 20:00 ET reopen, as described
    ///      in the contract documentation.
    function _afterRead(RoundData memory _round) internal virtual override view {
        super._afterRead(_round);

        require(_round.updatedAt + maxStaleness >= block.timestamp, MaxStalenessReached());

        if (_round.updatedAt + tradingStaleness < block.timestamp) {
            (uint256 dstStartTimestamp, uint256 dstEndTimestamp) = _getDSTBoundaries(block.timestamp);

            if (!ETTimestamp.isETWeekendTrading(block.timestamp, dstStartTimestamp, dstEndTimestamp, reopenTimeWait)) {
                revert TradingStalenessReached();
            } else {
                uint256 lastFridayCloseInUTC = ETTimestamp.getLastETFridayCloseInUTC(block.timestamp, dstStartTimestamp, dstEndTimestamp);
                require(_round.updatedAt + tradingStaleness >= lastFridayCloseInUTC, TradingStalenessReached());
            }
        }
    }

    /// @notice Returns the US daylight saving time boundaries for the UTC year of a timestamp.
    /// @dev Uses the UTC calendar year of `_timestamp`. Close to New Year the ET date can be in the
    ///      previous year, but both dates are in standard time, so the result is the same.
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @return Unix timestamp (UTC) when daylight saving time starts (second Sunday of March, 07:00 UTC).
    /// @return Unix timestamp (UTC) when daylight saving time ends (first Sunday of November, 06:00 UTC).
    function _getDSTBoundaries(uint256 _timestamp) internal pure returns (uint256, uint256) {
        (uint256 year, ,) = UnixTimestamp.getDate(_timestamp);

        return ETTimestamp.getETTransitionBoundariesInUTC(year);
    }
}