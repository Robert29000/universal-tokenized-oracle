// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { AggregatorV2V3Interface as IAggregatorV2V3 } from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV2V3Interface.sol";


import { IUniversalOracleBase } from "./interfaces/IUniversalOracleBase.sol";


abstract contract UniversalOracleBase is Ownable, IUniversalOracleBase {
    
    IAggregatorV2V3 public immutable aggregator;

    constructor(address _aggregator) Ownable(msg.sender) {
        require(_aggregator != address(0), AggregatorZeroAddress());

        aggregator = IAggregatorV2V3(_aggregator);
    }

    function _price() internal virtual view returns (uint256) {
        _beforeRead();

        RoundData memory round;
        (round.roundId, round.answer, round.startedAt, round.updatedAt, round.answeredInRound) = aggregator.latestRoundData();

        _afterRead(round);

        return uint256(round.answer);
    }

    function _beforeRead() internal virtual view {

    }

    function _afterRead(RoundData memory _round) internal virtual view {
        require(_round.answer > 0, PriceZero());
    }

    function decimals() external virtual override view returns (uint8) {
        return aggregator.decimals();
    }

    function description() external virtual override view returns (string memory) {
        return string.concat("Universal feed: ", aggregator.description());
    }
}