// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


/// @title PhaseAggregatorHelper
/// @author Robert29000
/// @notice Converts between the round id of a Chainlink proxy and the phase id and round id of its aggregator.
/// @dev A Chainlink proxy encodes its round id as `(phaseId << 64) | aggregatorRoundId`. The phase id is 16 bits
///      and the aggregator round id is 64 bits, so the proxy round id is 80 bits. The proxy increases the phase id
///      each time it changes its aggregator. Thus the proxy round ids increase across phases.
library PhaseAggregatorHelper {

    /// @dev Number of bits of the aggregator round id in a proxy round id.
    uint256 constant private PHASE_OFFSET = 64;


    /// @notice Returns the phase id and the aggregator round id of a proxy round id.
    /// @dev The phase id is bits 64 to 79 of `_proxyRoundId`. The aggregator round id is bits 0 to 63. The function
    ///      ignores the bits above bit 79.
    /// @param _proxyRoundId The round id of the proxy.
    /// @return The phase id.
    /// @return The round id of the aggregator of the phase.
    function extractPhaseIdAndRoundId(uint256 _proxyRoundId) internal pure returns (uint16, uint64) {
        uint16 phaseId = uint16(_proxyRoundId >> PHASE_OFFSET);
        uint64 aggregatorRoundId = uint64(_proxyRoundId);

        return (phaseId, aggregatorRoundId);
    }

    /// @notice Returns the proxy round id of a phase id and an aggregator round id.
    /// @dev Inverse of `extractPhaseIdAndRoundId`. The result is `(_phaseId << 64) | _aggregatorRoundId`.
    /// @param _phaseId The phase id.
    /// @param _aggregatorRoundId The round id of the aggregator of the phase.
    /// @return The round id of the proxy.
    function addPhaseIdToAggregatorRoundId(uint16 _phaseId, uint64 _aggregatorRoundId) internal pure returns (uint80) {
        return uint80(uint256(_phaseId) << PHASE_OFFSET | _aggregatorRoundId);
    }


}
