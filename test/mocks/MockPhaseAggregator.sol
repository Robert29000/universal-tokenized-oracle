// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {AggregatorV3Interface} from "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";

/// @notice Stand-in for a Chainlink proxy (AggregatorV3Interface) with a round history and phases.
/// @dev Round ids are proxy round ids: `(phaseId << 64) | aggregatorRoundId`. Each phase starts at aggregator round 1.
///      `getRoundData` reverts for a round that does not exist, so a test fails if the oracle reads outside
///      `[1, latest]` of a phase. Also deployed by the Python differential harness, so keep the ABI stable.
contract MockPhaseAggregator is AggregatorV3Interface {
    error NoDataPresent();

    struct Round {
        int256 answer;
        uint256 updatedAt;
    }

    uint8 public decimals;
    string public description;
    uint256 public constant version = 4;

    uint16 public phaseId = 1;
    mapping(uint16 => Round[]) internal rounds;

    constructor(uint8 _decimals, string memory _description) {
        decimals = _decimals;
        description = _description;
    }

    /// @notice Adds a round to the current phase. Returns its proxy round id.
    function pushRound(int256 _answer, uint256 _updatedAt) external returns (uint80) {
        rounds[phaseId].push(Round(_answer, _updatedAt));
        return _proxyId(phaseId, uint64(rounds[phaseId].length));
    }

    /// @notice Starts a new phase (a new aggregator behind the proxy). The new phase has no rounds.
    function newPhase() external {
        phaseId++;
    }

    /// @notice Replaces a round of a phase.
    function setRound(uint16 _phaseId, uint64 _aggregatorRoundId, int256 _answer, uint256 _updatedAt) external {
        rounds[_phaseId][_aggregatorRoundId - 1] = Round(_answer, _updatedAt);
    }

    function roundCount(uint16 _phaseId) external view returns (uint256) {
        return rounds[_phaseId].length;
    }

    function getRoundData(uint80 _roundId) external view returns (uint80, int256, uint256, uint256, uint80) {
        uint16 phase = uint16(_roundId >> 64);
        uint64 id = uint64(_roundId);
        if (id == 0 || id > rounds[phase].length) revert NoDataPresent();
        Round memory r = rounds[phase][id - 1];
        return (_roundId, r.answer, r.updatedAt, r.updatedAt, _roundId);
    }

    function latestRoundData() external view returns (uint80, int256, uint256, uint256, uint80) {
        uint256 n = rounds[phaseId].length;
        if (n == 0) revert NoDataPresent();
        Round memory r = rounds[phaseId][n - 1];
        uint80 id = _proxyId(phaseId, uint64(n));
        return (id, r.answer, r.updatedAt, r.updatedAt, id);
    }

    function _proxyId(uint16 _phaseId, uint64 _aggregatorRoundId) internal pure returns (uint80) {
        return uint80((uint256(_phaseId) << 64) | _aggregatorRoundId);
    }
}
