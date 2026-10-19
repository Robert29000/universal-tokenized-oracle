// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UniversalOracleBase} from "src/UniversalOracleBase.sol";
import {StalenessChecker} from "src/modules/StalenessChecker.sol";

/// @notice Concrete oracle composed of UniversalOracleBase + StalenessChecker only.
contract StalenessCheckerWrapper is StalenessChecker {
    constructor(address _aggregator, uint256 _maxStaleness, uint256 _tradingStaleness, uint256 _reopenTimeWait)
        UniversalOracleBase(_aggregator)
        StalenessChecker(_maxStaleness, _tradingStaleness, _reopenTimeWait)
    {}

    function exposed_price() external view returns (uint256) {
        return _price();
    }

    function exposed_afterRead(RoundData memory _round) external view {
        _afterRead(_round);
    }

    function exposed_getDSTBoundaries(uint256 _timestamp) external pure returns (uint256, uint256) {
        return _getDSTBoundaries(_timestamp);
    }
}
