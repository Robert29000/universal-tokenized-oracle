// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Minimal configurable stand-in for Backed/xStocks BackedAutoFeeToken.
/// @dev Implements only the views read by xStocksPauseConfigurator:
///      newMultiplierActivationTime(), multiplierUpdatesLength(), multiplierUpdates(uint256).
///      Mirrors the real token: index 0 of multiplierUpdates is the genesis sentinel {1e18, 1e18, 0}.
///      The length can be overridden (e.g. to 0) to exercise malformed-token behaviour.
contract MockBackedAutoFeeToken {
    error MockBackedAutoFeeTokenReverted();

    struct MultiplierUpdate {
        uint256 previousMultiplier;
        uint256 newMultiplier;
        uint256 activationTime;
    }

    MultiplierUpdate[] internal updates;

    uint256 internal pendingActivationTime;

    bool public lengthOverridden;
    uint256 public lengthOverride;

    bool public revertOnActivationTime;
    bool public revertOnLength;
    bool public revertOnUpdates;

    constructor() {
        updates.push(MultiplierUpdate(1e18, 1e18, 0));
    }

    // ---------------------------------------------------------------- setters

    function setNewMultiplierActivationTime(uint256 _time) external {
        pendingActivationTime = _time;
    }

    function pushUpdate(uint256 _previous, uint256 _new, uint256 _activationTime) external {
        updates.push(MultiplierUpdate(_previous, _new, _activationTime));
    }

    function popUpdate() external {
        updates.pop();
    }

    function clearUpdates() external {
        delete updates;
    }

    function setLengthOverride(bool _overridden, uint256 _length) external {
        lengthOverridden = _overridden;
        lengthOverride = _length;
    }

    function setReverts(bool _onActivationTime, bool _onLength, bool _onUpdates) external {
        revertOnActivationTime = _onActivationTime;
        revertOnLength = _onLength;
        revertOnUpdates = _onUpdates;
    }

    /// @notice Simulates an immediate multiplier update recorded at `_now` (no pending activation).
    function applyImmediateUpdate(uint256 _now) external {
        updates.push(MultiplierUpdate(1e18, 1e18, _now));
        pendingActivationTime = 0;
    }

    /// @notice Simulates a scheduled update: it is appended to the log and flagged as pending.
    function scheduleUpdate(uint256 _activationTime) external {
        updates.push(MultiplierUpdate(1e18, 1e18, _activationTime));
        pendingActivationTime = _activationTime;
    }

    /// @notice Simulates the token processing the pending update (pending flag cleared, log kept).
    function processPending() external {
        pendingActivationTime = 0;
    }

    // ---------------------------------------------------------------- views

    function multiplierUpdatesLength() external view returns (uint256) {
        if (revertOnLength) revert MockBackedAutoFeeTokenReverted();
        if (lengthOverridden) return lengthOverride;
        return updates.length;
    }

    function multiplierUpdates(uint256 index)
        external
        view
        returns (uint256 previousMultiplier, uint256 newMultiplier, uint256 activationTime)
    {
        if (revertOnUpdates) revert MockBackedAutoFeeTokenReverted();
        MultiplierUpdate memory u = updates[index];
        return (u.previousMultiplier, u.newMultiplier, u.activationTime);
    }

    function newMultiplierActivationTime() external view returns (uint256) {
        if (revertOnActivationTime) revert MockBackedAutoFeeTokenReverted();
        return pendingActivationTime;
    }
}
