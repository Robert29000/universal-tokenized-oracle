// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {PhaseAggregatorHelperWrapper} from "test/mocks/wrappers/PhaseAggregatorHelperWrapper.sol";

contract PhaseAggregatorHelperTest is Test {
    PhaseAggregatorHelperWrapper internal lib;

    // Chainlink proxy round id of phase 6, aggregator round 10551: 6 * 2^64 + 10551.
    uint80 internal constant PROXY_ROUND_ID = 110680464442257320247;

    function setUp() public {
        lib = new PhaseAggregatorHelperWrapper();
    }

    // ================================================================== extractPhaseIdAndRoundId

    function test_extractPhaseIdAndRoundId_KnownValue() public view {
        (uint16 phaseId, uint64 roundId) = lib.extractPhaseIdAndRoundId(PROXY_ROUND_ID);
        assertEq(phaseId, 6);
        assertEq(roundId, 10551);
    }

    function test_extractPhaseIdAndRoundId_PhaseZero() public view {
        // An aggregator that is not behind a proxy: the round id has no phase bits.
        (uint16 phaseId, uint64 roundId) = lib.extractPhaseIdAndRoundId(42);
        assertEq(phaseId, 0);
        assertEq(roundId, 42);
    }

    function test_extractPhaseIdAndRoundId_MaxValues() public view {
        (uint16 phaseId, uint64 roundId) = lib.extractPhaseIdAndRoundId(type(uint80).max);
        assertEq(phaseId, type(uint16).max);
        assertEq(roundId, type(uint64).max);
    }

    function test_extractPhaseIdAndRoundId_IgnoresBitsAbove79() public view {
        (uint16 phaseId, uint64 roundId) = lib.extractPhaseIdAndRoundId((uint256(1) << 80) | PROXY_ROUND_ID);
        assertEq(phaseId, 6);
        assertEq(roundId, 10551);
    }

    // ================================================================== addPhaseIdToAggregatorRoundId

    function test_addPhaseIdToAggregatorRoundId_KnownValue() public view {
        assertEq(lib.addPhaseIdToAggregatorRoundId(6, 10551), PROXY_ROUND_ID);
        assertEq(lib.addPhaseIdToAggregatorRoundId(2, 5), (uint256(2) << 64) | 5);
    }

    function test_addPhaseIdToAggregatorRoundId_Edges() public view {
        assertEq(lib.addPhaseIdToAggregatorRoundId(0, 0), 0);
        assertEq(lib.addPhaseIdToAggregatorRoundId(0, type(uint64).max), type(uint64).max);
        assertEq(lib.addPhaseIdToAggregatorRoundId(1, 0), uint80(1) << 64);
        assertEq(lib.addPhaseIdToAggregatorRoundId(type(uint16).max, type(uint64).max), type(uint80).max);
    }

    // ================================================================== fuzz

    function testFuzz_roundTrip_FromParts(uint16 _phaseId, uint64 _roundId) public view {
        (uint16 phaseId, uint64 roundId) = lib.extractPhaseIdAndRoundId(lib.addPhaseIdToAggregatorRoundId(_phaseId, _roundId));
        assertEq(phaseId, _phaseId);
        assertEq(roundId, _roundId);
    }

    function testFuzz_roundTrip_FromProxyRoundId(uint80 _proxyRoundId) public view {
        (uint16 phaseId, uint64 roundId) = lib.extractPhaseIdAndRoundId(_proxyRoundId);
        assertEq(lib.addPhaseIdToAggregatorRoundId(phaseId, roundId), _proxyRoundId);
    }

    /// @dev Proxy round ids increase with the phase id first, then with the aggregator round id.
    function testFuzz_addPhaseIdToAggregatorRoundId_Order(uint16 _phaseId, uint64 _a, uint64 _b) public view {
        vm.assume(_phaseId < type(uint16).max);
        assertGt(lib.addPhaseIdToAggregatorRoundId(_phaseId + 1, _a), lib.addPhaseIdToAggregatorRoundId(_phaseId, _b));
        if (_a < _b) {
            assertLt(lib.addPhaseIdToAggregatorRoundId(_phaseId, _a), lib.addPhaseIdToAggregatorRoundId(_phaseId, _b));
        }
    }
}
