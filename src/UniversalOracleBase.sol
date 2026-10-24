// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { AggregatorV2V3Interface as IAggregatorV2V3 } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";


import { IUniversalOracleBase } from "./interfaces/IUniversalOracleBase.sol";


/// @title UniversalOracleBase
/// @author Robert29000
/// @notice Base of the universal tokenized-stock oracle. It reads the latest price from a
///         Chainlink-compatible aggregator and runs validation hooks before and after each read.
/// @dev Price read flow in `_price()`:
///      1. `_beforeRead()`: checks that do not need the round data (for example L2 sequencer uptime
///         and corporate pause).
///      2. `aggregator.latestRoundData()` is read into a `RoundData` struct.
///      3. `_afterRead(round)`: checks on the round data (for example price > 0 and staleness).
///      4. `_adjustAnswer(round.answer)`: converts the validated answer into the returned price.
///      Modules inherit from this contract and override the hooks.
///      The deployer becomes the `Ownable` owner. Modules use the owner for their setters.
///      Trust assumption: the aggregator is a trusted Chainlink-compatible feed. Its decimals are
///      forwarded as-is and its description is returned with the prefix "Universal feed: ".
///      Only `answer` (via `_afterRead`) is checked by the base.
abstract contract UniversalOracleBase is Ownable, IUniversalOracleBase {
    
    /// @notice The Chainlink-compatible price feed that supplies the price.
    IAggregatorV2V3 public immutable aggregator;

    /// @notice Sets the price aggregator and makes the deployer the owner.
    /// @dev Reverts with `AggregatorZeroAddress` if `_aggregator` is the zero address.
    /// @param _aggregator Address of the Chainlink-compatible (AggregatorV2V3Interface) price feed.
    constructor(address _aggregator) Ownable(msg.sender) {
        require(_aggregator != address(0), AggregatorZeroAddress());

        aggregator = IAggregatorV2V3(_aggregator);
    }

    /// @notice Reads the latest price from the aggregator and validates it with the hooks.
    /// @dev Runs `_beforeRead()`, then `aggregator.latestRoundData()`, then `_afterRead(round)`, then
    ///      `_adjustAnswer(round.answer)`. Any hook can revert.
    /// @return The latest validated price, scaled by `decimals()`.
    function _price() internal virtual view returns (uint256) {
        _beforeRead();

        RoundData memory round;
        (round.roundId, round.answer, round.startedAt, round.updatedAt, round.answeredInRound) = aggregator.latestRoundData();

        _afterRead(round);

        return _adjustAnswer(round.answer);
    }

    /// @notice Hook that runs before the aggregator is read.
    /// @dev Empty in the base. Overrides must call `super._beforeRead()`.
    function _beforeRead() internal virtual view {

    }

    /// @notice Hook that runs after the aggregator is read, with the round data.
    /// @dev The base implementation reverts with `PriceZero` if `answer <= 0`.
    ///      Overrides must call `super._afterRead(_round)`.
    /// @param _round The round data returned by `aggregator.latestRoundData()`.
    function _afterRead(RoundData memory _round) internal virtual view {
        require(_round.answer > 0, PriceZero());
    }

    /// @notice Hook that converts the validated answer into the returned price.
    /// @dev Runs after `_afterRead`, which already checked that `_answer > 0`. The base implementation casts the
    ///      `int256` answer to `uint256`. Overrides can return another price, for example a smoothed price.
    /// @param _answer The `answer` of the round data returned by `aggregator.latestRoundData()`.
    /// @return The price, scaled by `decimals()`.
    function _adjustAnswer(int256 _answer) internal virtual view returns (uint256) {
        return uint256(_answer);
    }

    /// @inheritdoc IUniversalOracleBase
    /// @dev Returns the `decimals()` of the underlying aggregator.
    function decimals() external virtual override view returns (uint8) {
        return aggregator.decimals();
    }

    /// @inheritdoc IUniversalOracleBase
    /// @dev Returns the aggregator description with the prefix "Universal feed: ".
    function description() external virtual override view returns (string memory) {
        return string.concat("Universal feed: ", aggregator.description());
    }
}