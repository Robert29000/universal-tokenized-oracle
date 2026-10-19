// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IPauseConfigurator} from "src/modules/corporate_providers/interfaces/IPauseConfigurator.sol";

/// @notice Generic IPauseConfigurator with a settable pause flag and a forced-revert switch.
contract MockPauseConfigurator is IPauseConfigurator {
    error MockPauseConfiguratorReverted();

    bool public paused;
    bool public shouldRevert;

    function setPaused(bool _paused) external {
        paused = _paused;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function isPaused() external view returns (bool) {
        if (shouldRevert) revert MockPauseConfiguratorReverted();
        return paused;
    }
}
