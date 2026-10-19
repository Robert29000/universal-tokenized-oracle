// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IOraclePausable} from "src/modules/corporate_providers/interfaces/IRobinhoodOraclePausable.sol";

/// @notice Configurable stand-in for Robinhood's IOraclePausable.
contract MockRobinhoodOraclePausable is IOraclePausable {
    error MockOraclePausableReverted();

    bool internal paused;
    bool public shouldRevert;

    function setOraclePaused(bool _paused) external {
        paused = _paused;
        if (_paused) emit OraclePaused();
        else emit OracleUnpaused();
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function oraclePaused() external view returns (bool) {
        if (shouldRevert) revert MockOraclePausableReverted();
        return paused;
    }
}
