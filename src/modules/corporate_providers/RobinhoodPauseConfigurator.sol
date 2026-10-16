// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


import { IPauseConfigurator } from "./interfaces/IPauseConfigurator.sol";
import { IOraclePausable } from "./interfaces/IRobinhoodOraclePausable.sol";

contract RobinhoodPauseConfigurator is IPauseConfigurator {

    error OraclePausableZeroAddress();

    IOraclePausable immutable oraclePausable;

    constructor(address _oraclePausable) {
        require(_oraclePausable != address(0), OraclePausableZeroAddress());
        oraclePausable = IOraclePausable(_oraclePausable);
    }

    function isPaused() external view returns (bool) {
        return oraclePausable.oraclePaused();
    }

}