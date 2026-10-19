// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UniversalOracleBase} from "src/UniversalOracleBase.sol";
import {CorporatePauseChecker} from "src/modules/CorporatePauseChecker.sol";

/// @notice Concrete oracle composed of UniversalOracleBase + CorporatePauseChecker only.
contract CorporatePauseCheckerWrapper is CorporatePauseChecker {
    constructor(address _aggregator, address _pauseConfigurator)
        UniversalOracleBase(_aggregator)
        CorporatePauseChecker(_pauseConfigurator)
    {}

    function exposed_price() external view returns (uint256) {
        return _price();
    }

    function exposed_beforeRead() external view {
        _beforeRead();
    }

    function exposed_setPauseConfigurator(address _pauseConfigurator) external {
        _setPauseConfigurator(_pauseConfigurator);
    }
}
