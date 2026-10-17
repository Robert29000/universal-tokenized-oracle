// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "../UniversalOracleBase.sol";

import { ICorporatePauseChecker } from "./interfaces/ICorporatePauseChecker.sol";
import { IPauseConfigurator } from "./corporate_providers/interfaces/IPauseConfigurator.sol";

abstract contract CorporatePauseChecker is UniversalOracleBase, ICorporatePauseChecker {

    IPauseConfigurator public pauseConfigurator;
    
    constructor(address _pauseConfigurator) {
        _setPauseConfigurator(_pauseConfigurator);
    }

    function _corporatePauseCheck() internal virtual override view {
        bool isPaused = pauseConfigurator.isPaused();
        require(!isPaused, CorporatePaused());
    }

    function setPauseConfigurator(address _pauseConfigurator) external onlyOwner {
        _setPauseConfigurator(_pauseConfigurator);
    }

    function _setPauseConfigurator(address _pauseConfigurator) internal {
        require(_pauseConfigurator != address(0), PauseConfiguratorZeroAddress());
        require(_pauseConfigurator != address(pauseConfigurator), PauseConfiguratorEqualCurrent());

        pauseConfigurator = IPauseConfigurator(_pauseConfigurator);

        emit PauseConfiguratorSet(_pauseConfigurator);
    }

}