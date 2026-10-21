// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UniversalOracleBase} from "src/UniversalOracleBase.sol";
import {StalenessChecker} from "src/modules/StalenessChecker.sol";

/// @notice Concrete oracle composed of UniversalOracleBase + StalenessChecker only.
/// @dev Also deployed by the Python differential harness (test/differential/python/), so keep the ABI stable.
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

    function exposed_isETWeekendTrading(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd, uint256 _grace)
        external
        pure
        returns (bool)
    {
        return _isETWeekendTrading(_timestamp, _dstStart, _dstEnd, _grace);
    }

    function exposed_checkETWeekendTrading(uint256 _etTimestamp, uint256 _grace) external pure returns (bool) {
        return _checkETWeekendTrading(_etTimestamp, _grace);
    }

    function exposed_getLastETFridayCloseTimestampInUTC(uint256 _timestamp, uint256 _dstStart, uint256 _dstEnd)
        external
        pure
        returns (uint256)
    {
        return _getLastETFridayCloseTimestampInUTC(_timestamp, _dstStart, _dstEnd);
    }
}
