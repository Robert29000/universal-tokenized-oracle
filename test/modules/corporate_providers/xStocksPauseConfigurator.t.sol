// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {stdError} from "forge-std/StdError.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {xStocksPauseConfigurator} from "src/modules/corporate_providers/xStocksPauseConfigurator.sol";
import {IBackedAutoFeeToken} from "src/modules/corporate_providers/interfaces/IBackedAutoFeeToken.sol";
import {xStocksPauseConfiguratorWrapper} from "test/mocks/wrappers/xStocksPauseConfiguratorWrapper.sol";
import {MockBackedAutoFeeToken} from "test/mocks/MockBackedAutoFeeToken.sol";
import {MockRawResponder} from "test/mocks/MockAdversarial.sol";

/// @dev Pause semantics under test (w = pause_window, A = relevant activation time, t = block.timestamp):
///      - no explicit update ever (only the genesis entry)    -> never paused
///      - pending update in the future (A > t)                -> paused iff t + w > A   (i.e. A - t < w)
///      - pending update already due but unprocessed (A <= t) -> paused iff A + w > t   (i.e. t - A < w)
///      - no pending update, last logged update at A          -> paused iff A + w > t
///      Together: paused on the open interval (A - w, A + w).
contract xStocksPauseConfiguratorTest is Test {
    MockBackedAutoFeeToken internal token;
    xStocksPauseConfiguratorWrapper internal configurator;

    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    uint256 internal constant W = 1 hours;
    uint256 internal constant MIN = 1 seconds;
    uint256 internal constant MAX = 5 hours;
    uint256 internal constant NOW = 1_750_000_000;

    function setUp() public {
        vm.warp(NOW);
        token = new MockBackedAutoFeeToken();
        vm.prank(owner);
        configurator = new xStocksPauseConfiguratorWrapper(address(token), W);
    }

    // ================================================================== constructor

    function test_constructor_SetsState() public view {
        assertEq(configurator.pause_window(), W);
        assertEq(configurator.owner(), owner);
        assertEq(configurator.exposed_MIN_PAUSE_WINDOW(), MIN);
        assertEq(configurator.exposed_MAX_PAUSE_WINDOW(), MAX);
    }

    function test_constructor_EmitsPauseWindowSet() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectEmit(predicted);
        emit xStocksPauseConfigurator.PauseWindowSet(W);
        xStocksPauseConfigurator c = new xStocksPauseConfigurator(address(token), W);
        assertEq(address(c), predicted);
        assertEq(c.owner(), address(this));
    }

    function test_RevertWhen_constructor_BackedAutoFeeTokenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(xStocksPauseConfigurator.BackedAutoFeeTokenZeroAddress.selector));
        new xStocksPauseConfigurator(address(0), W);
    }

    function test_RevertWhen_constructor_PauseWindowZero() public {
        vm.expectRevert(abi.encodeWithSelector(xStocksPauseConfigurator.PauseWindowBelowMinimum.selector));
        new xStocksPauseConfigurator(address(token), 0);
    }

    function test_RevertWhen_constructor_PauseWindowAboveMaximum() public {
        vm.expectRevert(abi.encodeWithSelector(xStocksPauseConfigurator.PauseWindowAboveMaximum.selector));
        new xStocksPauseConfigurator(address(token), MAX + 1);
    }

    function test_constructor_PauseWindowAtMaximum() public {
        xStocksPauseConfigurator c = new xStocksPauseConfigurator(address(token), MAX);
        assertEq(c.pause_window(), MAX);
    }

    // ================================================================== setPauseWindow

    function test_setPauseWindow_UpdatesAndEmits() public {
        vm.expectEmit(address(configurator));
        emit xStocksPauseConfigurator.PauseWindowSet(2 hours);
        vm.prank(owner);
        configurator.setPauseWindow(2 hours);
        assertEq(configurator.pause_window(), 2 hours);
    }

    function test_setPauseWindow_LowestAccepted() public {
        vm.prank(owner);
        configurator.setPauseWindow(MIN + 1);
        assertEq(configurator.pause_window(), 2);
    }

    function test_setPauseWindow_HighestAccepted() public {
        vm.prank(owner);
        configurator.setPauseWindow(MAX);
        assertEq(configurator.pause_window(), MAX);
    }

    /// @notice NOTE (possible off-by-one): MIN_PAUSE_WINDOW (1s) itself is rejected (`>` MIN) while
    ///         MAX_PAUSE_WINDOW is accepted (`<=` MAX). Asserts current behaviour.
    function test_RevertWhen_setPauseWindow_EqualsMinimum() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(xStocksPauseConfigurator.PauseWindowBelowMinimum.selector));
        configurator.setPauseWindow(MIN);
    }

    function test_RevertWhen_setPauseWindow_Zero() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(xStocksPauseConfigurator.PauseWindowBelowMinimum.selector));
        configurator.setPauseWindow(0);
    }

    function test_RevertWhen_setPauseWindow_AboveMaximum() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(xStocksPauseConfigurator.PauseWindowAboveMaximum.selector));
        configurator.setPauseWindow(MAX + 1);
    }

    function test_RevertWhen_setPauseWindow_Uint256Max() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(xStocksPauseConfigurator.PauseWindowAboveMaximum.selector));
        configurator.setPauseWindow(type(uint256).max);
    }

    function test_RevertWhen_setPauseWindow_AlreadySet() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(xStocksPauseConfigurator.PauseWindowAlreadySet.selector));
        configurator.setPauseWindow(W);
    }

    function test_RevertWhen_setPauseWindow_CallerNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        configurator.setPauseWindow(2 hours);
    }

    function test_exposedSetPauseWindow_InternalHasNoAccessControl() public {
        vm.prank(stranger);
        configurator.exposed_setPauseWindow(2 hours);
        assertEq(configurator.pause_window(), 2 hours);
    }

    function testFuzz_setPauseWindow(uint256 _window) public {
        vm.prank(owner);
        if (_window <= MIN) {
            vm.expectRevert(abi.encodeWithSelector(xStocksPauseConfigurator.PauseWindowBelowMinimum.selector));
        } else if (_window > MAX) {
            vm.expectRevert(abi.encodeWithSelector(xStocksPauseConfigurator.PauseWindowAboveMaximum.selector));
        } else if (_window == W) {
            vm.expectRevert(abi.encodeWithSelector(xStocksPauseConfigurator.PauseWindowAlreadySet.selector));
        } else {
            vm.expectEmit(address(configurator));
            emit xStocksPauseConfigurator.PauseWindowSet(_window);
        }
        configurator.setPauseWindow(_window);
        assertEq(configurator.pause_window(), (_window > MIN && _window <= MAX) ? _window : W);
    }

    // ================================================================== isPaused: no updates

    function test_isPaused_NoUpdatesEver() public view {
        assertFalse(configurator.isPaused());
    }

    function test_isPaused_NoUpdatesDoesNotReadLog() public {
        vm.expectCall(address(token), abi.encodeCall(IBackedAutoFeeToken.multiplierUpdates, (0)), 0);
        configurator.isPaused();
    }

    // ================================================================== isPaused: processed update

    function test_isPaused_ProcessedUpdateBoundaries() public {
        token.applyImmediateUpdate(NOW);
        assertTrue(configurator.isPaused(), "at activation");
        vm.warp(NOW + W - 1);
        assertTrue(configurator.isPaused(), "activation + w - 1");
        vm.warp(NOW + W);
        assertFalse(configurator.isPaused(), "activation + w");
        vm.warp(NOW + 365 days);
        assertFalse(configurator.isPaused(), "long after");
    }

    function test_isPaused_ProcessedUpdateReadsLastEntry() public {
        token.pushUpdate(1e18, 1.1e18, NOW); // would pause on its own
        token.pushUpdate(1.1e18, 1.2e18, NOW - 2 * W); // latest entry, outside window
        vm.expectCall(address(token), abi.encodeCall(IBackedAutoFeeToken.multiplierUpdates, (2)), 1);
        assertFalse(configurator.isPaused());
    }

    function test_isPaused_ProcessedUpdateFutureActivationLogged() public {
        // Defensive: a logged activation in the future with no pending flag still pauses (A + w > t).
        token.pushUpdate(1e18, 1e18, NOW + 10 * W);
        assertTrue(configurator.isPaused());
    }

    function test_RevertWhen_isPaused_EmptyUpdateLog() public {
        // The real token always has the genesis sentinel at index 0; an empty log underflows.
        token.setLengthOverride(true, 0);
        vm.expectRevert(stdError.arithmeticError);
        configurator.isPaused();
    }

    function test_RevertWhen_isPaused_LastActivationOverflows() public {
        token.pushUpdate(1e18, 1e18, type(uint256).max);
        vm.expectRevert(stdError.arithmeticError);
        configurator.isPaused();
    }

    // ================================================================== isPaused: pending in the future

    function test_isPaused_PendingFutureBoundaries() public {
        uint256 a = NOW + 10 * W;
        token.scheduleUpdate(a);
        vm.warp(a - W - 1);
        assertFalse(configurator.isPaused(), "A - w - 1");
        vm.warp(a - W);
        assertFalse(configurator.isPaused(), "A - w");
        vm.warp(a - W + 1);
        assertTrue(configurator.isPaused(), "A - w + 1");
        vm.warp(a - 1);
        assertTrue(configurator.isPaused(), "A - 1");
    }

    function test_isPaused_PendingFarFuture() public {
        token.scheduleUpdate(type(uint256).max);
        assertFalse(configurator.isPaused());
    }

    function test_isPaused_PendingDoesNotReadLog() public {
        token.scheduleUpdate(NOW + 10 * W);
        vm.expectCall(address(token), abi.encodeCall(IBackedAutoFeeToken.multiplierUpdatesLength, ()), 0);
        configurator.isPaused();
    }

    // ================================================================== isPaused: pending, due, unprocessed

    function test_isPaused_PendingDueBoundaries() public {
        uint256 a = NOW + 10 * W;
        token.scheduleUpdate(a);
        vm.warp(a);
        assertTrue(configurator.isPaused(), "A");
        vm.warp(a + W - 1);
        assertTrue(configurator.isPaused(), "A + w - 1");
        vm.warp(a + W);
        assertFalse(configurator.isPaused(), "A + w");
    }

    function test_isPaused_PendingAndProcessedAgreeAfterActivation() public {
        uint256 a = NOW + 10 * W;
        token.scheduleUpdate(a);
        vm.warp(a + W / 2);
        bool pendingResult = configurator.isPaused();
        token.processPending();
        assertEq(configurator.isPaused(), pendingResult);
        assertTrue(pendingResult);
    }

    // ================================================================== isPaused: lifecycle

    function test_isPaused_FullLifecycle() public {
        // 1. immediate update at NOW: paused for w
        token.applyImmediateUpdate(NOW);
        assertTrue(configurator.isPaused());
        vm.warp(NOW + W);
        assertFalse(configurator.isPaused());

        // 2. schedule an update 10w ahead: paused only within w before it
        uint256 a = NOW + 10 * W;
        token.scheduleUpdate(a);
        assertFalse(configurator.isPaused());
        vm.warp(a - W + 1);
        assertTrue(configurator.isPaused());

        // 3. activation passes, token processes it later: stays paused until A + w
        vm.warp(a + 10 minutes);
        assertTrue(configurator.isPaused());
        token.processPending();
        assertTrue(configurator.isPaused());
        vm.warp(a + W);
        assertFalse(configurator.isPaused());
    }

    function test_isPaused_WindowChangeAppliesImmediately() public {
        token.applyImmediateUpdate(NOW);
        vm.warp(NOW + W);
        assertFalse(configurator.isPaused());
        vm.prank(owner);
        configurator.setPauseWindow(W + 1);
        assertTrue(configurator.isPaused());
    }

    // ================================================================== isPaused: token failures

    function test_RevertWhen_isPaused_ActivationTimeReverts() public {
        token.setReverts(true, false, false);
        vm.expectRevert(abi.encodeWithSelector(MockBackedAutoFeeToken.MockBackedAutoFeeTokenReverted.selector));
        configurator.isPaused();
    }

    function test_RevertWhen_isPaused_UpdatesLengthReverts() public {
        token.setReverts(false, true, false);
        vm.expectRevert(abi.encodeWithSelector(MockBackedAutoFeeToken.MockBackedAutoFeeTokenReverted.selector));
        configurator.isPaused();
    }

    function test_RevertWhen_isPaused_UpdatesReverts() public {
        token.applyImmediateUpdate(NOW);
        token.setReverts(false, false, true);
        vm.expectRevert(abi.encodeWithSelector(MockBackedAutoFeeToken.MockBackedAutoFeeTokenReverted.selector));
        configurator.isPaused();
    }

    // ================================================================== fuzz

    function _setWindow(uint256 _w) internal returns (uint256) {
        _w = bound(_w, MIN + 1, MAX);
        if (_w != configurator.pause_window()) {
            vm.prank(owner);
            configurator.setPauseWindow(_w);
        }
        return _w;
    }

    function testFuzz_isPaused_NoUpdatesNeverPaused(uint256 _now, uint256 _w) public {
        _setWindow(_w);
        vm.warp(bound(_now, 0, type(uint64).max));
        assertFalse(configurator.isPaused());
    }

    function testFuzz_isPaused_ProcessedUpdate(uint256 _activation, uint256 _now, uint256 _w) public {
        _w = _setWindow(_w);
        _activation = bound(_activation, 1, type(uint64).max);
        _now = bound(_now, _activation, type(uint64).max);
        token.applyImmediateUpdate(_activation);
        vm.warp(_now);
        assertEq(configurator.isPaused(), _now - _activation < _w);
    }

    function testFuzz_isPaused_PendingFuture(uint256 _activation, uint256 _now, uint256 _w) public {
        _w = _setWindow(_w);
        _now = bound(_now, 0, type(uint64).max);
        _activation = bound(_activation, _now + 1, type(uint128).max);
        token.scheduleUpdate(_activation);
        vm.warp(_now);
        assertEq(configurator.isPaused(), _activation - _now < _w);
    }

    function testFuzz_isPaused_PendingDue(uint256 _activation, uint256 _now, uint256 _w) public {
        _w = _setWindow(_w);
        _activation = bound(_activation, 1, type(uint64).max);
        _now = bound(_now, _activation, type(uint64).max);
        token.scheduleUpdate(_activation);
        vm.warp(_now);
        assertEq(configurator.isPaused(), _now - _activation < _w);
    }

    /// @dev Around a pending activation A the feed is paused exactly on the open interval (A - w, A + w).
    function testFuzz_isPaused_SymmetricOpenInterval(uint256 _w, uint256 _offset, bool _before) public {
        _w = _setWindow(_w);
        _offset = bound(_offset, 0, 2 * _w);
        uint256 a = NOW + 1 days;
        token.scheduleUpdate(a);
        vm.warp(_before ? a - _offset : a + _offset);
        assertEq(configurator.isPaused(), _offset < _w);
    }

    /// @dev Exact borders for every valid window: A - w and A + w are unpaused, one second inside is paused.
    function testFuzz_isPaused_Borders(uint256 _w) public {
        _w = _setWindow(_w);
        uint256 a = NOW + 1 days;
        token.scheduleUpdate(a);

        vm.warp(a - _w);
        assertFalse(configurator.isPaused(), "A - w");
        vm.warp(a - _w + 1);
        assertTrue(configurator.isPaused(), "A - w + 1");
        vm.warp(a + _w - 1);
        assertTrue(configurator.isPaused(), "A + w - 1 (pending)");
        vm.warp(a + _w);
        assertFalse(configurator.isPaused(), "A + w (pending)");

        token.processPending();
        vm.warp(a + _w - 1);
        assertTrue(configurator.isPaused(), "A + w - 1 (processed)");
        vm.warp(a + _w);
        assertFalse(configurator.isPaused(), "A + w (processed)");
    }

    /// @dev With n >= 2 log entries and nothing pending, only the last entry matters.
    function testFuzz_isPaused_OnlyLastLogEntryMatters(uint8 _n, uint256 _lastAge, uint256 _w) public {
        _w = _setWindow(_w);
        uint256 n = bound(_n, 1, 20);
        _lastAge = bound(_lastAge, 0, 2 * MAX);
        for (uint256 i = 0; i < n - 1; i++) {
            token.pushUpdate(1e18, 1e18, NOW); // older entries that would pause on their own
        }
        token.pushUpdate(1e18, 1e18, NOW - _lastAge);
        assertEq(configurator.isPaused(), _lastAge < _w);
    }

    // ================================================================== ownership

    function test_setPauseWindow_AfterOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        configurator.transferOwnership(newOwner);
        assertEq(configurator.owner(), newOwner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        configurator.setPauseWindow(2 hours);

        vm.prank(newOwner);
        configurator.setPauseWindow(2 hours);
        assertEq(configurator.pause_window(), 2 hours);
    }

    function test_RevertWhen_transferOwnership_CallerNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        configurator.transferOwnership(stranger);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        configurator.renounceOwnership();
        assertEq(configurator.owner(), owner);
    }

    // ================================================================== malformed / misconfigured token

    function test_RevertWhen_isPaused_TokenHasNoCode() public {
        xStocksPauseConfigurator c = new xStocksPauseConfigurator(makeAddr("eoa"), W);
        vm.expectRevert(bytes(""));
        c.isPaused();
    }

    function test_RevertWhen_isPaused_TokenReturnsShortData() public {
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(MockRawResponder.Mode.Return, hex"01");
        xStocksPauseConfigurator c = new xStocksPauseConfigurator(address(raw), W);
        vm.expectRevert(bytes(""));
        c.isPaused();
    }

    function test_isPaused_ScheduledUpdateOverridden() public {
        // The real token pops an overridden future entry and replaces it. Only the new schedule matters.
        uint256 a = NOW + 10 * W;
        token.scheduleUpdate(NOW + W / 2); // would pause now
        assertTrue(configurator.isPaused());
        token.popUpdate();
        token.scheduleUpdate(a);
        assertFalse(configurator.isPaused());
        vm.warp(a - W + 1);
        assertTrue(configurator.isPaused());
    }
}
