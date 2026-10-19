// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {xStocksPauseConfigurator} from "src/modules/corporate_providers/xStocksPauseConfigurator.sol";

/// @notice Exposes xStocksPauseConfigurator internals (constants and _setPauseWindow).
contract xStocksPauseConfiguratorWrapper is xStocksPauseConfigurator {
    constructor(address _token, uint256 _pauseWindow) xStocksPauseConfigurator(_token, _pauseWindow) {}

    function exposed_setPauseWindow(uint256 _pauseWindow) external {
        _setPauseWindow(_pauseWindow);
    }

    function exposed_MIN_PAUSE_WINDOW() external pure returns (uint256) {
        return MIN_PAUSE_WINDOW;
    }

    function exposed_MAX_PAUSE_WINDOW() external pure returns (uint256) {
        return MAX_PAUSE_WINDOW;
    }
}
