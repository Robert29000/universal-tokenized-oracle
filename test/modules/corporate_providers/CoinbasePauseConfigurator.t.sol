// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {CoinbasePauseConfigurator} from "src/modules/corporate_providers/CoinbasePauseConfigurator.sol";
import {IOracleRegistry} from "src/modules/corporate_providers/interfaces/ICoinbaseOracleRegistry.sol";
import {MockCoinbaseOracleRegistry} from "test/mocks/MockCoinbaseOracleRegistry.sol";
import {MockRawResponder} from "test/mocks/MockAdversarial.sol";

contract CoinbasePauseConfiguratorTest is Test {
    MockCoinbaseOracleRegistry internal registry;
    CoinbasePauseConfigurator internal configurator;

    address internal token = makeAddr("token");
    address internal otherToken = makeAddr("otherToken");

    function setUp() public {
        registry = new MockCoinbaseOracleRegistry();
        configurator = new CoinbasePauseConfigurator(address(registry), token);
    }

    function test_RevertWhen_constructor_OracleRegistryZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(CoinbasePauseConfigurator.OracleRegistryZeroAddress.selector));
        new CoinbasePauseConfigurator(address(0), token);
    }

    function test_RevertWhen_constructor_TokenZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(CoinbasePauseConfigurator.TokenZeroAddress.selector));
        new CoinbasePauseConfigurator(address(registry), address(0));
    }

    function test_RevertWhen_constructor_BothZeroRegistryCheckedFirst() public {
        vm.expectRevert(abi.encodeWithSelector(CoinbasePauseConfigurator.OracleRegistryZeroAddress.selector));
        new CoinbasePauseConfigurator(address(0), address(0));
    }

    function test_isPaused_DefaultFalse() public view {
        assertFalse(configurator.isPaused());
    }

    function test_isPaused_ReflectsRegistryFlag() public {
        registry.setOraclePaused(token, true);
        assertTrue(configurator.isPaused());
        registry.setOraclePaused(token, false);
        assertFalse(configurator.isPaused());
    }

    function test_isPaused_QueriesConfiguredToken() public {
        vm.expectCall(address(registry), abi.encodeCall(IOracleRegistry.getOracleParams, (token)), 1);
        configurator.isPaused();
    }

    function test_isPaused_IgnoresOtherTokens() public {
        registry.setOraclePaused(otherToken, true);
        assertFalse(configurator.isPaused());
    }

    function test_isPaused_IgnoresMultiplier() public {
        registry.setOracleParams(token, 0, false);
        assertFalse(configurator.isPaused());
        registry.setOracleParams(token, type(uint256).max, true);
        assertTrue(configurator.isPaused());
    }

    function test_RevertWhen_isPaused_RegistryReverts() public {
        registry.setShouldRevert(true);
        vm.expectRevert(abi.encodeWithSelector(MockCoinbaseOracleRegistry.MockOracleRegistryReverted.selector));
        configurator.isPaused();
    }

    function testFuzz_isPaused(uint256 _multiplier, bool _paused, bool _otherPaused) public {
        registry.setOracleParams(token, _multiplier, _paused);
        registry.setOracleParams(otherToken, _multiplier, _otherPaused);
        assertEq(configurator.isPaused(), _paused);
    }

    function test_RevertWhen_isPaused_RegistryHasNoCode() public {
        CoinbasePauseConfigurator c = new CoinbasePauseConfigurator(makeAddr("eoa"), token);
        vm.expectRevert(bytes(""));
        c.isPaused();
    }

    function test_RevertWhen_isPaused_RegistryReturnsNonBoolFlag() public {
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(MockRawResponder.Mode.Return, abi.encode(uint256(1e18), uint256(2)));
        CoinbasePauseConfigurator c = new CoinbasePauseConfigurator(address(raw), token);
        vm.expectRevert(bytes(""));
        c.isPaused();
    }

    function test_RevertWhen_isPaused_RegistryReturnsShortData() public {
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(MockRawResponder.Mode.Return, abi.encode(uint256(1e18))); // missing `paused`
        CoinbasePauseConfigurator c = new CoinbasePauseConfigurator(address(raw), token);
        vm.expectRevert(bytes(""));
        c.isPaused();
    }
}
