// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IStalenessChecker {

    struct DSTBoundaries {
        uint256 dstStartTimestamp;
        uint256 dstEndTimestamp;
    }

    error InvalidYear();
    error MaxStalenessZero();
    error TradingStalenessZero();
    error MaxStalenessReached();
    error TradingStalenessReached();

    function maxStaleness() external view returns (uint256);
    function tradingStaleness() external view returns (uint256);

}