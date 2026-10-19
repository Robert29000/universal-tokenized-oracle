// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {RobinhoodPauseConfigurator} from "src/modules/corporate_providers/RobinhoodPauseConfigurator.sol";
import {IOraclePausable} from "src/modules/corporate_providers/interfaces/IRobinhoodOraclePausable.sol";
import {MockRobinhoodOraclePausable} from "test/mocks/MockRobinhoodOraclePausable.sol";
import {MockRawResponder} from "test/mocks/MockAdversarial.sol";

contract RobinhoodPauseConfiguratorTest is Test {
    MockRobinhoodOraclePausable internal pausable;
    RobinhoodPauseConfigurator internal configurator;

    function setUp() public {
        pausable = new MockRobinhoodOraclePausable();
        configurator = new RobinhoodPauseConfigurator(address(pausable));
    }

    function test_RevertWhen_constructor_OraclePausableZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(RobinhoodPauseConfigurator.OraclePausableZeroAddress.selector));
        new RobinhoodPauseConfigurator(address(0));
    }

    function test_isPaused_DefaultFalse() public view {
        assertFalse(configurator.isPaused());
    }

    function test_isPaused_ReflectsOraclePaused() public {
        pausable.setOraclePaused(true);
        assertTrue(configurator.isPaused());
        pausable.setOraclePaused(false);
        assertFalse(configurator.isPaused());
    }

    function test_isPaused_QueriesOraclePausable() public {
        vm.expectCall(address(pausable), abi.encodeCall(IOraclePausable.oraclePaused, ()), 1);
        configurator.isPaused();
    }

    function test_RevertWhen_isPaused_OraclePausableReverts() public {
        pausable.setShouldRevert(true);
        vm.expectRevert(abi.encodeWithSelector(MockRobinhoodOraclePausable.MockOraclePausableReverted.selector));
        configurator.isPaused();
    }

    function test_RevertWhen_isPaused_OraclePausableHasNoCode() public {
        // A non-contract address passes the constructor check but makes every read revert.
        RobinhoodPauseConfigurator c = new RobinhoodPauseConfigurator(makeAddr("eoa"));
        vm.expectRevert(bytes(""));
        c.isPaused();
    }

    function test_RevertWhen_isPaused_OraclePausableReturnsNonBool() public {
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(MockRawResponder.Mode.Return, abi.encode(uint256(2)));
        RobinhoodPauseConfigurator c = new RobinhoodPauseConfigurator(address(raw));
        vm.expectRevert(bytes(""));
        c.isPaused();
    }

    function testFuzz_isPaused(bool _paused) public {
        pausable.setOraclePaused(_paused);
        assertEq(configurator.isPaused(), _paused);
    }
}
