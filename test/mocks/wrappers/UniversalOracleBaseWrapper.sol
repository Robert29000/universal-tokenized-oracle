// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UniversalOracleBase} from "src/UniversalOracleBase.sol";

/// @notice Minimal concrete UniversalOracleBase (no modules) exposing the internal read pipeline.
contract UniversalOracleBaseWrapper is UniversalOracleBase {
    constructor(address _aggregator) UniversalOracleBase(_aggregator) {}

    function exposed_price() external view returns (uint256) {
        return _price();
    }

    function exposed_beforeRead() external view {
        _beforeRead();
    }

    function exposed_afterRead(RoundData memory _round) external view {
        _afterRead(_round);
    }
}
