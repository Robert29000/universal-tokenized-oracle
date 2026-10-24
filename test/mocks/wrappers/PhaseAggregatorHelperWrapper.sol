// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {PhaseAggregatorHelper} from "src/libraries/PhaseAggregatorHelper.sol";

/// @notice Exposes every internal PhaseAggregatorHelper library function as an external call.
contract PhaseAggregatorHelperWrapper {
    function extractPhaseIdAndRoundId(uint256 _proxyRoundId) external pure returns (uint16, uint64) {
        return PhaseAggregatorHelper.extractPhaseIdAndRoundId(_proxyRoundId);
    }

    function addPhaseIdToAggregatorRoundId(uint16 _phaseId, uint64 _aggregatorRoundId) external pure returns (uint80) {
        return PhaseAggregatorHelper.addPhaseIdToAggregatorRoundId(_phaseId, _aggregatorRoundId);
    }
}
