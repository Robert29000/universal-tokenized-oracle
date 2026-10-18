// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";

import { IPauseConfigurator } from "./interfaces/IPauseConfigurator.sol";
import { IBackedAutoFeeToken } from "./interfaces/IBackedAutoFeeToken.sol";


/// @title xStocksPauseConfigurator
/// @author Robert29000
/// @notice Pause configurator for xStocks (Backed Finance) tokenized stocks. It reports a pause during a time
///         window around each multiplier update of the token (for example a stock split or a dividend).
/// @dev The pause is calculated from the multiplier schedule of the `IBackedAutoFeeToken`, not from the
///      token transfer pause (`IBackedToken.isPaused`). With `w = pause_window`, `isPaused()` returns true:
///      - Before a scheduled update: when `activationTime - w < block.timestamp < activationTime`.
///      - After an update: when `activationTime <= block.timestamp < activationTime + w`.
///      Both ends of the pause are exclusive: the pause is the open interval
///      `(activationTime - w, activationTime + w)`.
///      If no update is pending (`newMultiplierActivationTime() == 0`), the result is
///      `block.timestamp < activationTime + w` for the last entry in `multiplierUpdates` (the lower bound
///      is not checked). If the log holds only the genesis entry, the result is false.
///      If an update is pending, only the pending update is checked, not earlier entries in the log.
///      Trust assumption: the Backed token and its multiplier updater are trusted.
///      The deployer becomes the owner and can change `pause_window`.
contract xStocksPauseConfigurator is Ownable, IPauseConfigurator {

    /// @notice The Backed auto-fee token address given to the constructor is the zero address.
    error BackedAutoFeeTokenZeroAddress();
    /// @notice The pause window is less than or equal to `MIN_PAUSE_WINDOW`.
    error PauseWindowBelowMinimum();
    /// @notice The pause window is greater than `MAX_PAUSE_WINDOW`.
    error PauseWindowAboveMaximum();
    /// @notice The new pause window is the same as the current one.
    error PauseWindowAlreadySet();

    /// @notice Emitted when the pause window is set (in the constructor or by the owner).
    /// @param pause_window The new pause window, in seconds.
    event PauseWindowSet(uint256 pause_window);

    /// @dev Exclusive lower bound of `pause_window`, in seconds.
    uint256 constant MIN_PAUSE_WINDOW = 1 seconds;
    /// @dev Inclusive upper bound of `pause_window`, in seconds.
    uint256 constant MAX_PAUSE_WINDOW = 5 hours;

    /// @dev The xStocks (Backed) token whose multiplier updates are read.
    IBackedAutoFeeToken immutable backedAutoFeeToken;
    /// @notice Length of the pause before and after each multiplier activation, in seconds.
    uint256 public pause_window;

    /// @notice Sets the xStocks token and the initial pause window. The deployer becomes the owner.
    /// @dev Reverts with `BackedAutoFeeTokenZeroAddress` if the token address is zero, and with the
    ///      `_setPauseWindow` errors if the window is out of range. Emits `PauseWindowSet`.
    /// @param _backedAutoFeeToken Address of the xStocks token that implements `IBackedAutoFeeToken`.
    /// @param _pause_window Initial pause window, in seconds.
    constructor(address _backedAutoFeeToken, uint256 _pause_window) Ownable(msg.sender) {
        require(_backedAutoFeeToken != address(0), BackedAutoFeeTokenZeroAddress());
        backedAutoFeeToken = IBackedAutoFeeToken(_backedAutoFeeToken);

        _setPauseWindow(_pause_window);
    }

    /// @notice Sets the length of the pause before and after each multiplier activation.
    /// @dev Only the owner can call this function. Reverts with the `_setPauseWindow` errors. Emits `PauseWindowSet`.
    /// @param _pause_window The new pause window, in seconds.
    function setPauseWindow(uint256 _pause_window) external onlyOwner {
        _setPauseWindow(_pause_window);
    }


    /// @notice Validates and stores a new pause window.
    /// @dev Reverts with `PauseWindowBelowMinimum` if `_pause_window <= MIN_PAUSE_WINDOW`, `PauseWindowAboveMaximum`
    ///      if `_pause_window > MAX_PAUSE_WINDOW`, and `PauseWindowAlreadySet` if the value does not change.
    ///      Emits `PauseWindowSet`.
    /// @param _pause_window The new pause window, in seconds.
    function _setPauseWindow(uint256 _pause_window) internal {
        require(_pause_window > MIN_PAUSE_WINDOW, PauseWindowBelowMinimum());
        require(_pause_window <= MAX_PAUSE_WINDOW, PauseWindowAboveMaximum());
        require(_pause_window != pause_window, PauseWindowAlreadySet());

        pause_window = _pause_window;

        emit PauseWindowSet(_pause_window);
    }

    /// @inheritdoc IPauseConfigurator
    /// @dev Returns true if `block.timestamp` is less than `pause_window` seconds before or after a multiplier
    ///      activation. See the contract documentation for the cases. Reverts with an arithmetic underflow
    ///      panic if no update is pending and `multiplierUpdatesLength()` returns 0 (the Backed token always
    ///      stores a genesis entry at index 0).
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

                return newMultiplierActivationTime + pause_window > block.timestamp;
            }
        }

    }


}