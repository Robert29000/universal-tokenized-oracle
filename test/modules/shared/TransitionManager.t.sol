// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {ITransitionManager} from "src/modules/shared/interfaces/ITransitionManager.sol";

import {TransitionManagerWrapper} from "test/mocks/wrappers/TransitionManagerWrapper.sol";

contract TransitionManagerTest is Test {
    TransitionManagerWrapper internal manager;

    uint256 internal constant WINDOW = 10 minutes;
    uint256 internal constant MAX_WINDOW = 4 hours;

    // Transition as uint8 (see TransitionManagerWrapper)
    uint8 internal constant OVERNIGHT_TO_PRE = 0;
    uint8 internal constant PRE_TO_REGULAR = 1;
    uint8 internal constant REGULAR_TO_POST = 2;
    uint8 internal constant POST_TO_OVERNIGHT = 3;

    uint256 internal constant AT_0400 = 4 hours;
    uint256 internal constant AT_0930 = 9 hours + 30 minutes;
    uint256 internal constant AT_1600 = 16 hours;
    uint256 internal constant AT_2000 = 20 hours;

    uint256 internal constant DAY = 20_000 days; // any ET date

    function setUp() public {
        manager = new TransitionManagerWrapper(WINDOW);
    }

    // ------------------------------------------------------------ helpers

    function _boundaryOf(uint8 _transition) internal pure returns (uint256) {
        return [AT_0400, AT_0930, AT_1600, AT_2000][_transition];
    }

    // ================================================================== constructor and constants

    function test_constructor_SetsDefaultWindow() public view {
        assertEq(manager.defaultTransitionWindow(), WINDOW);
        assertEq(manager.owner(), address(this));
        for (uint8 i = 0; i < 4; i++) {
            (bool isSet, uint256 window) = manager.transitionWindows(ITransitionManager.Transition(i));
            assertFalse(isSet);
            assertEq(window, 0);
        }
    }

    function test_constructor_EmitsDefaultTransitionWindowSet() public {
        vm.expectEmit(true, true, true, true);
        emit ITransitionManager.DefaultTransitionWindowSet(WINDOW);
        new TransitionManagerWrapper(WINDOW);
    }

    function test_constructor_BoundaryValuesAccepted() public {
        TransitionManagerWrapper m = new TransitionManagerWrapper(0);
        assertEq(m.defaultTransitionWindow(), 0);
        m = new TransitionManagerWrapper(MAX_WINDOW - 1);
        assertEq(m.defaultTransitionWindow(), MAX_WINDOW - 1);
    }

    function test_RevertWhen_constructor_DefaultWindowEqualsMax() public {
        vm.expectRevert(abi.encodeWithSelector(ITransitionManager.DefaultTransitionWindowTooLong.selector));
        new TransitionManagerWrapper(MAX_WINDOW);
    }

    function testFuzz_constructor(uint256 _window) public {
        if (_window >= MAX_WINDOW) {
            vm.expectRevert(abi.encodeWithSelector(ITransitionManager.DefaultTransitionWindowTooLong.selector));
        }
        TransitionManagerWrapper m = new TransitionManagerWrapper(_window);
        if (_window < MAX_WINDOW) assertEq(m.defaultTransitionWindow(), _window);
    }

    function test_constants() public view {
        assertEq(manager.OVERNIGHT_TO_PRE_MARKET_OFFSET(), AT_0400);
        assertEq(manager.PRE_MARKET_TO_REGULAR_OFFSET(), AT_0930);
        assertEq(manager.REGULAR_TO_POST_MARKET_OFFSET(), AT_1600);
        assertEq(manager.POST_MARKET_TO_OVERNIGHT_OFFSET(), AT_2000);
        assertEq(manager.MAX_TRANSITION_WINDOW(), MAX_WINDOW);
    }

    /// @dev The windows cannot overlap: the shortest time between two boundaries is MAX_TRANSITION_WINDOW, and the
    ///      20:00 window ends before 00:00.
    function test_constants_WindowsCannotOverlap() public view {
        uint256 maxWindow = manager.MAX_TRANSITION_WINDOW();
        assertLe(AT_0400 + maxWindow, AT_0930);
        assertLe(AT_0930 + maxWindow, AT_1600);
        assertLe(AT_1600 + maxWindow, AT_2000);
        assertLe(AT_2000 + maxWindow, 1 days);
    }

    // ================================================================== setDefaultTransitionWindow

    function test_setDefaultTransitionWindow() public {
        vm.expectEmit(true, true, true, true, address(manager));
        emit ITransitionManager.DefaultTransitionWindowSet(1 hours);
        manager.setDefaultTransitionWindow(1 hours);
        assertEq(manager.defaultTransitionWindow(), 1 hours);
        manager.setDefaultTransitionWindow(0);
        assertEq(manager.defaultTransitionWindow(), 0);
    }

    function test_RevertWhen_setDefaultTransitionWindow_SameValue() public {
        vm.expectRevert(abi.encodeWithSelector(ITransitionManager.TransitionWindowAlreadySet.selector));
        manager.setDefaultTransitionWindow(WINDOW);
    }

    function test_RevertWhen_setDefaultTransitionWindow_TooLong() public {
        vm.expectRevert(abi.encodeWithSelector(ITransitionManager.DefaultTransitionWindowTooLong.selector));
        manager.setDefaultTransitionWindow(MAX_WINDOW);
        manager.setDefaultTransitionWindow(MAX_WINDOW - 1);
        assertEq(manager.defaultTransitionWindow(), MAX_WINDOW - 1);
    }

    function test_RevertWhen_setDefaultTransitionWindow_NotOwner() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        manager.setDefaultTransitionWindow(1 hours);
    }

    function testFuzz_setDefaultTransitionWindow(uint256 _window) public {
        bytes4 err;
        if (_window == WINDOW) err = ITransitionManager.TransitionWindowAlreadySet.selector;
        else if (_window >= MAX_WINDOW) err = ITransitionManager.DefaultTransitionWindowTooLong.selector;

        if (err != bytes4(0)) vm.expectRevert(abi.encodeWithSelector(err));
        manager.setDefaultTransitionWindow(_window);
        assertEq(manager.defaultTransitionWindow(), err == bytes4(0) ? _window : WINDOW);
    }

    // ================================================================== setTransitionWindow

    function test_setTransitionWindow() public {
        ITransitionManager.Transition t = ITransitionManager.Transition.PreMarketToRegular;
        vm.expectEmit(true, true, true, true, address(manager));
        emit ITransitionManager.TransitionWindowSet(t, true, 1 hours);
        manager.setTransitionWindow(t, true, 1 hours);
        (bool isSet, uint256 window) = manager.transitionWindows(t);
        assertTrue(isSet);
        assertEq(window, 1 hours);
        // The same value is accepted again.
        manager.setTransitionWindow(t, true, 1 hours);
        // The other transitions do not change.
        (isSet, window) = manager.transitionWindows(ITransitionManager.Transition.RegularToPostMarket);
        assertFalse(isSet);
        assertEq(window, 0);
    }

    function test_RevertWhen_setTransitionWindow_TooLong() public {
        ITransitionManager.Transition t = ITransitionManager.Transition.PostMarketToOvernight;
        vm.expectRevert(abi.encodeWithSelector(ITransitionManager.TransitionWindowTooLong.selector));
        manager.setTransitionWindow(t, true, MAX_WINDOW);
        // The bound applies also if the window is not used.
        vm.expectRevert(abi.encodeWithSelector(ITransitionManager.TransitionWindowTooLong.selector));
        manager.setTransitionWindow(t, false, MAX_WINDOW);
        manager.setTransitionWindow(t, true, MAX_WINDOW - 1);
    }

    function test_RevertWhen_setTransitionWindow_NotOwner() public {
        address alice = makeAddr("alice");
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, alice));
        manager.setTransitionWindow(ITransitionManager.Transition.OvernightToPreMarket, true, 1 hours);
    }

    function testFuzz_setTransitionWindow(uint8 _transition, bool _isSet, uint256 _window) public {
        ITransitionManager.Transition t = ITransitionManager.Transition(bound(_transition, 0, 3));
        if (_window >= MAX_WINDOW) {
            vm.expectRevert(abi.encodeWithSelector(ITransitionManager.TransitionWindowTooLong.selector));
        }
        manager.setTransitionWindow(t, _isSet, _window);
        if (_window < MAX_WINDOW) {
            (bool isSet, uint256 window) = manager.transitionWindows(t);
            assertEq(isSet, _isSet);
            assertEq(window, _window);
        }
    }

    // ================================================================== _getTransitionOffset

    function test_getTransitionOffset() public view {
        for (uint8 i = 0; i < 4; i++) {
            assertEq(manager.exposed_getTransitionOffset(i), _boundaryOf(i));
        }
    }

    // ================================================================== _getTransitionWindow

    function test_getTransitionWindow_DefaultWindow() public view {
        for (uint8 i = 0; i < 4; i++) {
            assertEq(manager.exposed_getTransitionWindow(i), WINDOW);
        }
    }

    function test_getTransitionWindow_OwnWindowReplacesDefault() public {
        manager.setTransitionWindow(ITransitionManager.Transition.PreMarketToRegular, true, 1 hours);
        manager.setTransitionWindow(ITransitionManager.Transition.RegularToPostMarket, true, 0);
        manager.setTransitionWindow(ITransitionManager.Transition.PostMarketToOvernight, false, 2 hours);
        assertEq(manager.exposed_getTransitionWindow(OVERNIGHT_TO_PRE), WINDOW, "not set");
        assertEq(manager.exposed_getTransitionWindow(PRE_TO_REGULAR), 1 hours, "own window");
        assertEq(manager.exposed_getTransitionWindow(REGULAR_TO_POST), 0, "own zero window");
        assertEq(manager.exposed_getTransitionWindow(POST_TO_OVERNIGHT), WINDOW, "is_set false");
        manager.setDefaultTransitionWindow(1 minutes);
        assertEq(manager.exposed_getTransitionWindow(OVERNIGHT_TO_PRE), 1 minutes, "new default");
        assertEq(manager.exposed_getTransitionWindow(PRE_TO_REGULAR), 1 hours, "own window kept");
    }

    // ================================================================== _getTransitionBoundary

    function test_getTransitionBoundary() public view {
        for (uint8 i = 0; i < 4; i++) {
            assertEq(manager.exposed_getTransitionBoundary(i, DAY), DAY + _boundaryOf(i));
            assertEq(manager.exposed_getTransitionBoundary(i, 0), _boundaryOf(i));
        }
    }

    // ================================================================== _isTransition

    function test_isTransition_DefaultWindowEdges() public view {
        for (uint8 i = 0; i < 4; i++) {
            uint256 boundary = DAY + _boundaryOf(i);
            assertFalse(manager.exposed_isTransition(i, boundary - 1, DAY), "boundary - 1");
            assertFalse(manager.exposed_isTransition(i, boundary, DAY), "boundary");
            assertTrue(manager.exposed_isTransition(i, boundary + 1, DAY), "boundary + 1");
            assertTrue(manager.exposed_isTransition(i, boundary + WINDOW, DAY), "end of window");
            assertFalse(manager.exposed_isTransition(i, boundary + WINDOW + 1, DAY), "after window");
        }
    }

    function test_isTransition_OwnWindowReplacesDefault() public {
        uint256 boundary = DAY + AT_0930;
        manager.setTransitionWindow(ITransitionManager.Transition.PreMarketToRegular, true, 1 hours);
        assertTrue(manager.exposed_isTransition(PRE_TO_REGULAR, boundary + 1 hours, DAY));
        assertFalse(manager.exposed_isTransition(PRE_TO_REGULAR, boundary + 1 hours + 1, DAY));
        // A shorter own window is used too.
        manager.setTransitionWindow(ITransitionManager.Transition.PreMarketToRegular, true, 1);
        assertTrue(manager.exposed_isTransition(PRE_TO_REGULAR, boundary + 1, DAY));
        assertFalse(manager.exposed_isTransition(PRE_TO_REGULAR, boundary + 2, DAY));
    }

    function test_isTransition_NotSetUsesDefault() public {
        uint256 boundary = DAY + AT_1600;
        manager.setTransitionWindow(ITransitionManager.Transition.RegularToPostMarket, false, 1 hours);
        assertTrue(manager.exposed_isTransition(REGULAR_TO_POST, boundary + WINDOW, DAY));
        assertFalse(manager.exposed_isTransition(REGULAR_TO_POST, boundary + WINDOW + 1, DAY));
    }

    function test_isTransition_DefaultChangeAppliesToNotSetOnly() public {
        manager.setTransitionWindow(ITransitionManager.Transition.OvernightToPreMarket, true, WINDOW);
        manager.setDefaultTransitionWindow(1 hours);
        assertFalse(manager.exposed_isTransition(OVERNIGHT_TO_PRE, DAY + AT_0400 + WINDOW + 1, DAY), "own window");
        assertTrue(manager.exposed_isTransition(PRE_TO_REGULAR, DAY + AT_0930 + 1 hours, DAY), "new default");
    }

    function test_isTransition_ZeroWindowNeverInTransition() public {
        uint256 boundary = DAY + AT_0400;
        manager.setTransitionWindow(ITransitionManager.Transition.OvernightToPreMarket, true, 0);
        assertFalse(manager.exposed_isTransition(OVERNIGHT_TO_PRE, boundary, DAY));
        assertFalse(manager.exposed_isTransition(OVERNIGHT_TO_PRE, boundary + 1, DAY));
    }

    function test_RevertWhen_isTransition_InvalidEnumValue() public {
        vm.expectRevert(); // Panic 0x21: enum conversion out of range
        manager.exposed_isTransition(4, 0, 0);
    }

    /// @dev The result is `boundary < now <= boundary + window`, with the own window if set, else the default.
    function testFuzz_isTransition(uint8 _transition, bool _isSet, uint256 _window, uint256 _day, uint256 _delta)
        public
    {
        uint8 t = uint8(bound(_transition, 0, 3));
        _window = bound(_window, 0, MAX_WINDOW - 1);
        manager.setTransitionWindow(ITransitionManager.Transition(t), _isSet, _window);
        uint256 day = bound(_day, 0, 3_000_000) * 1 days; // ET dates up to year 9999
        uint256 boundary = day + _boundaryOf(t);
        uint256 current = boundary - 2 + bound(_delta, 0, MAX_WINDOW + 4);

        uint256 window = _isSet ? _window : WINDOW;
        bool expected = current > boundary && current <= boundary + window;
        assertEq(manager.exposed_isTransition(t, current, day), expected);
        assertEq(manager.exposed_getTransitionWindow(t), window);
        assertEq(manager.exposed_getTransitionBoundary(t, day), boundary);
    }
}
