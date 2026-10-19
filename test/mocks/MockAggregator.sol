// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @notice Configurable stand-in for a Chainlink price feed (AggregatorV3Interface).
/// @dev Every return value can be set from tests, and every view can be forced to revert.
contract MockAggregator is AggregatorV3Interface {
    error MockAggregatorReverted();

    uint8 public decimalsValue;
    string public descriptionValue;
    uint256 public versionValue = 4;

    uint80 public roundId;
    int256 public answer;
    uint256 public startedAt;
    uint256 public updatedAt;
    uint80 public answeredInRound;

    bool public shouldRevert;

    constructor(uint8 _decimals, string memory _description) {
        decimalsValue = _decimals;
        descriptionValue = _description;
    }

    function setDecimals(uint8 _decimals) external {
        decimalsValue = _decimals;
    }

    function setDescription(string calldata _description) external {
        descriptionValue = _description;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function setRoundData(
        uint80 _roundId,
        int256 _answer,
        uint256 _startedAt,
        uint256 _updatedAt,
        uint80 _answeredInRound
    ) public {
        roundId = _roundId;
        answer = _answer;
        startedAt = _startedAt;
        updatedAt = _updatedAt;
        answeredInRound = _answeredInRound;
    }

    /// @notice Convenience setter: bumps the round and sets answer / updatedAt (startedAt = updatedAt).
    function setAnswer(int256 _answer, uint256 _updatedAt) external {
        uint80 next = roundId + 1;
        setRoundData(next, _answer, _updatedAt, _updatedAt, next);
    }

    function decimals() external view returns (uint8) {
        if (shouldRevert) revert MockAggregatorReverted();
        return decimalsValue;
    }

    function description() external view returns (string memory) {
        if (shouldRevert) revert MockAggregatorReverted();
        return descriptionValue;
    }

    function version() external view returns (uint256) {
        return versionValue;
    }

    function getRoundData(uint80) external view returns (uint80, int256, uint256, uint256, uint80) {
        if (shouldRevert) revert MockAggregatorReverted();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        if (shouldRevert) revert MockAggregatorReverted();
        return (roundId, answer, startedAt, updatedAt, answeredInRound);
    }
}
