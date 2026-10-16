// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


interface IPauseConfigurator {
    function isPaused() external view returns (bool);
}