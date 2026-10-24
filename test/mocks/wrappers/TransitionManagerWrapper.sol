// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {TransitionManager} from "src/modules/shared/TransitionManager.sol";

/// @notice Concrete TransitionManager without an oracle. The deployer becomes the owner.
contract TransitionManagerWrapper is TransitionManager {
    constructor(uint256 _defaultTransitionWindow) Ownable(msg.sender) TransitionManager(_defaultTransitionWindow) {}

    /// @dev `_transition` is the `Transition` enum as uint8 (OvernightToPreMarket = 0 ... PostMarketToOvernight = 3).
    function exposed_isTransition(uint8 _transition, uint256 _etCurrentTimestamp, uint256 _etDayTimestamp)
        external
        view
        returns (bool)
    {
        return _isTransition(Transition(_transition), _etCurrentTimestamp, _etDayTimestamp);
    }

    /// @dev `_transition` is the `Transition` enum as uint8.
    function exposed_getTransitionOffset(uint8 _transition) external pure returns (uint256) {
        return _getTransitionOffset(Transition(_transition));
    }

    /// @dev `_transition` is the `Transition` enum as uint8.
    function exposed_getTransitionWindow(uint8 _transition) external view returns (uint256) {
        return _getTransitionWindow(Transition(_transition));
    }

    /// @dev `_transition` is the `Transition` enum as uint8.
    function exposed_getTransitionBoundary(uint8 _transition, uint256 _etDayTimestamp) external pure returns (uint256) {
        return _getTransitionBoundary(Transition(_transition), _etDayTimestamp);
    }
}
