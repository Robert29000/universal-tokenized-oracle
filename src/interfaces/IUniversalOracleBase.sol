// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IUniversalOracleBase {

    struct RoundData {
    uint80 roundId;
    int256 answer;
    uint256 startedAt;
    uint256 updatedAt;
    uint80 answeredInRound;
}

    error AggregatorZeroAddress();
    error PriceZero();

    
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);
}