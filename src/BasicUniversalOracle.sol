// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import { UniversalOracleBase } from "./UniversalOracleBase.sol";
import { L2SequencerChecker } from "./modules/L2SequencerChecker.sol";
import { StalenessChecker } from "./modules/StalenessChecker.sol";
import { CorporatePauseChecker } from "./modules/CorporatePauseChecker.sol";

contract BasicUniversalOracle is L2SequencerChecker, StalenessChecker, CorporatePauseChecker {
    constructor(
        address _aggregator,
        address _sequencerAggregator,
        uint256 _downtimeWait,
        uint256 _maxStaleness,
        uint256 _tradingStaleness,
        uint256 _reopenTimeWait,
        address _pauseConfigurator
    )
        UniversalOracleBase(_aggregator)
        L2SequencerChecker(_sequencerAggregator, _downtimeWait)
        StalenessChecker(_maxStaleness, _tradingStaleness, _reopenTimeWait)
        CorporatePauseChecker(_pauseConfigurator)
    {}

    function _beforeRead() internal view override(UniversalOracleBase, L2SequencerChecker, CorporatePauseChecker) {
        super._beforeRead();
    }

    function _afterRead(RoundData memory _round) internal view override(UniversalOracleBase, StalenessChecker) {
        super._afterRead(_round);
    }
}
