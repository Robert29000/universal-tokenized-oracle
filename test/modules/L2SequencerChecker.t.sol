// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IUniversalOracleBase} from "src/interfaces/IUniversalOracleBase.sol";
import {IL2SequencerChecker} from "src/modules/interfaces/IL2SequencerChecker.sol";
import {L2SequencerCheckerWrapper} from "test/mocks/wrappers/L2SequencerCheckerWrapper.sol";
import {MockAggregator} from "test/mocks/MockAggregator.sol";
import {MockSequencerUptimeFeed} from "test/mocks/MockSequencerUptimeFeed.sol";
import {MockRawResponder} from "test/mocks/MockAdversarial.sol";

contract L2SequencerCheckerTest is Test {
    MockAggregator internal feed;
    MockSequencerUptimeFeed internal sequencer;
    L2SequencerCheckerWrapper internal oracle;

    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant WAIT = 1 hours;
    uint256 internal constant NOW = 1_750_000_000;

    function setUp() public {
        vm.warp(NOW);
        feed = new MockAggregator(8, "AAPL / USD");
        feed.setAnswer(200e8, NOW);
        sequencer = new MockSequencerUptimeFeed();
        sequencer.setStatus(0, NOW - 2 days); // up for 2 days

        vm.prank(owner);
        oracle = new L2SequencerCheckerWrapper(address(feed), address(sequencer), WAIT);
    }

    // ------------------------------------------------------------------ constructor

    function test_constructor_SetsState() public view {
        assertEq(address(oracle.sequencerAggregator()), address(sequencer));
        assertEq(address(oracle.aggregator()), address(feed));
        assertEq(oracle.downtimeWait(), WAIT);
        assertEq(oracle.owner(), owner);
        assertEq(oracle.exposed_MIN_DOWNTIME_WAIT(), 1 seconds);
        assertEq(oracle.exposed_MAX_DOWNTIME_WAIT(), 1 days);
    }

    function test_constructor_EmitsDowntimeWaitSet() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectEmit(predicted);
        emit IL2SequencerChecker.DowntimeWaitSet(WAIT);
        L2SequencerCheckerWrapper o = new L2SequencerCheckerWrapper(address(feed), address(sequencer), WAIT);
        assertEq(address(o), predicted);
    }

    function test_RevertWhen_constructor_SequencerAggregatorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.SequencerAggregatorZeroAddress.selector));
        new L2SequencerCheckerWrapper(address(feed), address(0), WAIT);
    }

    function test_RevertWhen_constructor_AggregatorZeroAddress() public {
        // UniversalOracleBase's constructor runs first.
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.AggregatorZeroAddress.selector));
        new L2SequencerCheckerWrapper(address(0), address(0), WAIT);
    }

    function test_RevertWhen_constructor_DowntimeWaitZero() public {
        // In the constructor the "current" value is 0, so 0 hits the minimum check first.
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.DowntimeWaitBelowMinimum.selector));
        new L2SequencerCheckerWrapper(address(feed), address(sequencer), 0);
    }

    function test_RevertWhen_constructor_DowntimeWaitAboveMaximum() public {
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.DowntimeWaitAboveMaximum.selector));
        new L2SequencerCheckerWrapper(address(feed), address(sequencer), 1 days);
    }

    // ------------------------------------------------------------------ setDowntimeWait

    function test_setDowntimeWait_UpdatesAndEmits() public {
        vm.expectEmit(address(oracle));
        emit IL2SequencerChecker.DowntimeWaitSet(2 hours);
        vm.prank(owner);
        oracle.setDowntimeWait(2 hours);
        assertEq(oracle.downtimeWait(), 2 hours);
    }

    function test_setDowntimeWait_LowestAccepted() public {
        vm.prank(owner);
        oracle.setDowntimeWait(2);
        assertEq(oracle.downtimeWait(), 2);
    }

    function test_setDowntimeWait_HighestAccepted() public {
        vm.prank(owner);
        oracle.setDowntimeWait(1 days - 1);
        assertEq(oracle.downtimeWait(), 1 days - 1);
    }

    /// @notice NOTE (possible off-by-one): MIN_DOWNTIME_WAIT itself (1s) is rejected because the check is
    ///         `> MIN` while the maximum check is `< MAX`; both bounds are exclusive. Asserts current behaviour.
    function test_RevertWhen_setDowntimeWait_EqualsMinimum() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.DowntimeWaitBelowMinimum.selector));
        oracle.setDowntimeWait(1);
    }

    function test_RevertWhen_setDowntimeWait_Zero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.DowntimeWaitBelowMinimum.selector));
        oracle.setDowntimeWait(0);
    }

    function test_RevertWhen_setDowntimeWait_EqualsMaximum() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.DowntimeWaitAboveMaximum.selector));
        oracle.setDowntimeWait(1 days);
    }

    function test_RevertWhen_setDowntimeWait_Uint256Max() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.DowntimeWaitAboveMaximum.selector));
        oracle.setDowntimeWait(type(uint256).max);
    }

    function test_RevertWhen_setDowntimeWait_EqualCurrent() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.DowntimeWaitEqualCurrent.selector));
        oracle.setDowntimeWait(WAIT);
    }

    function test_RevertWhen_setDowntimeWait_CallerNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oracle.setDowntimeWait(2 hours);
    }

    function test_exposedSetDowntimeWait_InternalHasNoAccessControl() public {
        vm.prank(stranger);
        oracle.exposed_setDowntimeWait(3 hours);
        assertEq(oracle.downtimeWait(), 3 hours);
    }

    function testFuzz_setDowntimeWait(uint256 _wait) public {
        vm.prank(owner);
        if (_wait <= 1) {
            vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.DowntimeWaitBelowMinimum.selector));
        } else if (_wait >= 1 days) {
            vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.DowntimeWaitAboveMaximum.selector));
        } else if (_wait == WAIT) {
            vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.DowntimeWaitEqualCurrent.selector));
        } else {
            vm.expectEmit(address(oracle));
            emit IL2SequencerChecker.DowntimeWaitSet(_wait);
        }
        oracle.setDowntimeWait(_wait);
        assertEq(oracle.downtimeWait(), (_wait > 1 && _wait < 1 days) ? _wait : WAIT);
    }

    // ------------------------------------------------------------------ _beforeRead

    function test_beforeRead_SequencerUpAndGraceOver() public view {
        oracle.exposed_beforeRead();
        assertEq(oracle.exposed_price(), 200e8);
    }

    function test_beforeRead_GraceEndsExactlyNow() public {
        sequencer.setStatus(0, NOW - WAIT);
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_GraceEndsOneSecondLater() public {
        sequencer.setStatus(0, NOW - WAIT + 1);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.GracePeriodNotOver.selector));
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_SequencerJustCameUp() public {
        sequencer.setStatus(0, NOW);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.GracePeriodNotOver.selector));
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_StartedAtInFuture() public {
        sequencer.setStatus(0, NOW + 1);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.GracePeriodNotOver.selector));
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_SequencerDown() public {
        sequencer.setStatus(1, NOW - 2 days);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.SequencerDown.selector));
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_SequencerDownTakesPrecedenceOverGrace() public {
        sequencer.setStatus(1, NOW);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.SequencerDown.selector));
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_UnexpectedStatusValues() public {
        sequencer.setStatus(-1, NOW - 2 days);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.SequencerDown.selector));
        oracle.exposed_beforeRead();

        sequencer.setStatus(2, NOW - 2 days);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.SequencerDown.selector));
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_SequencerFeedReverts() public {
        sequencer.setShouldRevert(true);
        vm.expectRevert(abi.encodeWithSelector(MockAggregator.MockAggregatorReverted.selector));
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_StartedAtOverflows() public {
        sequencer.setStatus(0, type(uint256).max);
        vm.expectRevert(stdError.arithmeticError);
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_price_SequencerDownBlocksFeedRead() public {
        sequencer.setStatus(1, NOW - 2 days);
        // The pre-read hook reverts before the price feed is queried.
        vm.expectCall(address(feed), abi.encodeCall(MockAggregator.latestRoundData, ()), 0);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.SequencerDown.selector));
        oracle.exposed_price();
    }

    function test_RevertWhen_price_ZeroAnswerAfterSequencerCheck() public {
        feed.setAnswer(0, NOW);
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.PriceZero.selector));
        oracle.exposed_price();
    }

    function testFuzz_beforeRead(int256 _answer, uint256 _startedAt, uint256 _now) public {
        _now = bound(_now, 0, type(uint64).max);
        _startedAt = bound(_startedAt, 1, type(uint64).max);
        vm.warp(_now);
        sequencer.setStatus(_answer, _startedAt);

        if (_answer != 0) {
            vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.SequencerDown.selector));
        } else if (_startedAt + WAIT > _now) {
            vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.GracePeriodNotOver.selector));
        }
        oracle.exposed_beforeRead();
    }

    // ------------------------------------------------------------------ startedAt vs updatedAt

    /// @dev Chainlink uptime feeds refresh updatedAt on same-status reports but keep startedAt at the last
    ///      status change. The wait must be measured from startedAt.
    function test_beforeRead_UsesStartedAtNotUpdatedAt() public {
        sequencer.setStatus(0, NOW - 2 days);
        sequencer.heartbeat(NOW); // fresh report, status unchanged
        oracle.exposed_beforeRead();

        sequencer.setStatus(0, NOW); // just came back up ...
        sequencer.setRoundData(9, 0, NOW, NOW - 2 days, 9); // ... with an old updatedAt
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.GracePeriodNotOver.selector));
        oracle.exposed_beforeRead();
    }

    function test_beforeRead_DowntimeWaitChangeAppliesImmediately() public {
        sequencer.setStatus(0, NOW - 90 minutes);
        oracle.exposed_beforeRead();
        vm.prank(owner);
        oracle.setDowntimeWait(2 hours);
        vm.expectRevert(abi.encodeWithSelector(IL2SequencerChecker.GracePeriodNotOver.selector));
        oracle.exposed_beforeRead();
    }

    // ------------------------------------------------------------------ malformed / misconfigured feed

    function test_RevertWhen_beforeRead_SequencerFeedHasNoCode() public {
        // The constructor only rejects address(0); an EOA passes but every read reverts without data.
        L2SequencerCheckerWrapper o = new L2SequencerCheckerWrapper(address(feed), makeAddr("eoa"), WAIT);
        vm.expectRevert(bytes(""));
        o.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_SequencerFeedReturnsShortData() public {
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(MockRawResponder.Mode.Return, abi.encode(uint80(1), int256(0))); // 2 of 5 words
        L2SequencerCheckerWrapper o = new L2SequencerCheckerWrapper(address(feed), address(raw), WAIT);
        vm.expectRevert(bytes(""));
        o.exposed_beforeRead();
    }

    // ------------------------------------------------------------------ ownership

    function test_setDowntimeWait_AfterOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        oracle.transferOwnership(newOwner);
        assertEq(oracle.owner(), newOwner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        oracle.setDowntimeWait(2 hours);

        vm.prank(newOwner);
        oracle.setDowntimeWait(2 hours);
        assertEq(oracle.downtimeWait(), 2 hours);
    }

    function test_RevertWhen_transferOwnership_CallerNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oracle.transferOwnership(stranger);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oracle.renounceOwnership();
        assertEq(oracle.owner(), owner);
    }
}
