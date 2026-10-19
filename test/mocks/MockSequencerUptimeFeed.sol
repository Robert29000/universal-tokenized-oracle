// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {MockAggregator} from "./MockAggregator.sol";

/// @notice Configurable stand-in for a Chainlink L2 sequencer uptime feed.
/// @dev answer == 0 means the sequencer is up, answer == 1 means it is down.
///      startedAt is the time of the last status change. As in Chainlink's L2 sequencer uptime feeds,
///      a status report that does not change the status only refreshes updatedAt (see `heartbeat`),
///      so updatedAt can be later than startedAt.
contract MockSequencerUptimeFeed is MockAggregator {
    int256 public constant UP = 0;
    int256 public constant DOWN = 1;

    constructor() MockAggregator(0, "L2 Sequencer Uptime Status Feed") {}

    function setStatus(int256 _answer, uint256 _startedAt) external {
        uint80 next = roundId + 1;
        setRoundData(next, _answer, _startedAt, _startedAt, next);
    }

    /// @notice Same-status report: only updatedAt moves, startedAt (last status change) is kept.
    function heartbeat(uint256 _updatedAt) external {
        updatedAt = _updatedAt;
    }
}
