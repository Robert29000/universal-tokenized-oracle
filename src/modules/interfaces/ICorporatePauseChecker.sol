// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

interface ICorporatePauseChecker {
    error PauseConfiguratorZeroAddress();
    error PauseConfiguratorEqualCurrent();
    error CorporatePaused();


    event PauseConfiguratorSet(address pauseConfigurator);
}