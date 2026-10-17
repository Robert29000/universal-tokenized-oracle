// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IUniversalOracleBase {

    error AggregatorZeroAddress();
    error PriceZero();

    
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);
}