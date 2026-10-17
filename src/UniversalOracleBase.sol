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
        _chainUptimeCheck();
        _corporatePauseCheck();

        (, int256 price, , uint256 updatedAt, ) = aggregator.latestRoundData();

        _checkStaleness(updatedAt);
        _checkPrice(price);

        return uint256(price);
    }

    function _chainUptimeCheck() internal virtual view {

    }

    function _corporatePauseCheck() internal virtual view {

    }

    function _checkStaleness(uint256 _updatedAt) internal virtual view {

    }

    function _checkPrice(int256 price) internal virtual view {
        require(price > 0, PriceZero());
    }

    function decimals() external virtual override view returns (uint8) {
        return aggregator.decimals();
    }

    function description() external virtual override view returns (string memory) {
        return string.concat("Universal feed: ", aggregator.description());
    }
}