// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IPauseConfigurator } from "../interfaces/IPauseConfigurator.sol";
import { IBackedAutoFeeToken } from "./interfaces/IBackedAutoFeeToken.sol";


contract xStocksPauseConfigurator is Ownable, IPauseConfigurator {

    error BackedAutoFeeTokenZeroAddress();
    error PauseWindowBelowMinimum();
    error PauseWindowAboveMaximum();
    error PauseWindowAlreadySet();

    event PauseWindowSet(uint256 pause_window);

    uint256 constant MIN_PAUSE_WINDOW = 1 seconds;
    uint256 constant MAX_PAUSE_WINDOW = 5 hours;

    IBackedAutoFeeToken immutable backedAutoFeeToken;
    uint256 public pause_window;

    constructor(address _backedAutoFeeToken, uint256 _pause_window) Ownable(msg.sender) {
        require(_backedAutoFeeToken != address(0), BackedAutoFeeTokenZeroAddress());
        backedAutoFeeToken = IBackedAutoFeeToken(_backedAutoFeeToken);

        _setPauseWindow(_pause_window);
    }

    function setPauseWindow(uint256 _pause_window) external onlyOwner {
        _setPauseWindow(_pause_window);
    }


    function _setPauseWindow(uint256 _pause_window) internal {
        require(_pause_window > MIN_PAUSE_WINDOW, PauseWindowBelowMinimum());
        require(_pause_window <= MAX_PAUSE_WINDOW, PauseWindowAboveMaximum());
        require(_pause_window != pause_window, PauseWindowAlreadySet());

        pause_window = _pause_window;

        emit PauseWindowSet(_pause_window);
    }

    function isPaused() external view returns (bool) {
        IBackedAutoFeeToken _backedAutoFeeToken = backedAutoFeeToken;

        uint256 newMultiplierActivationTime = _backedAutoFeeToken.newMultiplierActivationTime();

        if (newMultiplierActivationTime == 0) {
            // This means either we don't have new updates, or update was already processed
            uint256 multipliersHistoryLength = _backedAutoFeeToken.multiplierUpdatesLength();

            if (multipliersHistoryLength == 1) {
                // This means we don't have any updates
                return false;
            }

            // This means we have at least one update
            (,, uint256 lastActivationTime) = _backedAutoFeeToken.multiplierUpdates(multipliersHistoryLength - 1);

            return lastActivationTime + pause_window > block.timestamp;
        } else {
            // This means we have an update, and it can be in the future, or not yet processed
            if (newMultiplierActivationTime > block.timestamp) {

                return block.timestamp + pause_window > newMultiplierActivationTime;
            } else {

                return newMultiplierActivationTime + pause_window < block.timestamp;
            }
        }

    }


}