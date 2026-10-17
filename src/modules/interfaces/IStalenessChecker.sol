// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface IStalenessChecker {

    error MaxStalenessZero();
    error TradingStalenessZero();
    error MaxStalenessReached();
    error TradingStalenessReached();
    error MaxStalenessLessThanTradingStaleness();
    error ReopenTimeWaitGreaterThanTradingStaleness();

    function maxStaleness() external view returns (uint256);
    function tradingStaleness() external view returns (uint256);
    function reopenTimeWait() external view returns (uint256);

}