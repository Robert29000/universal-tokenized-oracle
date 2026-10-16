// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IUniversalOracleBase {

    error AggregatorZeroAddress();
    
    function decimals() external view returns (uint8);

    function description() external view returns (string memory);
}