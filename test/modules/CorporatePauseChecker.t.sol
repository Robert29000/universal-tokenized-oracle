// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

import {IUniversalOracleBase} from "src/interfaces/IUniversalOracleBase.sol";
import {ICorporatePauseChecker} from "src/modules/interfaces/ICorporatePauseChecker.sol";
import {CorporatePauseCheckerWrapper} from "test/mocks/wrappers/CorporatePauseCheckerWrapper.sol";
import {MockAggregator} from "test/mocks/MockAggregator.sol";
import {MockPauseConfigurator} from "test/mocks/MockPauseConfigurator.sol";
import {MockRawResponder, StateChangingPauseConfigurator} from "test/mocks/MockAdversarial.sol";

contract CorporatePauseCheckerTest is Test {
    MockAggregator internal feed;
    MockPauseConfigurator internal configurator;
    MockPauseConfigurator internal otherConfigurator;
    CorporatePauseCheckerWrapper internal oracle;

    address internal owner = makeAddr("owner");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        vm.warp(1_750_000_000);
        feed = new MockAggregator(8, "NVDA / USD");
        feed.setAnswer(120e8, block.timestamp);
        configurator = new MockPauseConfigurator();
        otherConfigurator = new MockPauseConfigurator();

        vm.prank(owner);
        oracle = new CorporatePauseCheckerWrapper(address(feed), address(configurator));
    }

    // ------------------------------------------------------------------ constructor

    function test_constructor_SetsState() public view {
        assertEq(address(oracle.pauseConfigurator()), address(configurator));
        assertEq(address(oracle.aggregator()), address(feed));
        assertEq(oracle.owner(), owner);
    }

    function test_constructor_EmitsPauseConfiguratorSet() public {
        address predicted = vm.computeCreateAddress(address(this), vm.getNonce(address(this)));
        vm.expectEmit(predicted);
        emit ICorporatePauseChecker.PauseConfiguratorSet(address(configurator));
        CorporatePauseCheckerWrapper o = new CorporatePauseCheckerWrapper(address(feed), address(configurator));
        assertEq(address(o), predicted);
    }

    function test_RevertWhen_constructor_PauseConfiguratorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(ICorporatePauseChecker.PauseConfiguratorZeroAddress.selector));
        new CorporatePauseCheckerWrapper(address(feed), address(0));
    }

    function test_RevertWhen_constructor_AggregatorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.AggregatorZeroAddress.selector));
        new CorporatePauseCheckerWrapper(address(0), address(configurator));
    }

    // ------------------------------------------------------------------ setPauseConfigurator

    function test_setPauseConfigurator_UpdatesAndEmits() public {
        vm.expectEmit(address(oracle));
        emit ICorporatePauseChecker.PauseConfiguratorSet(address(otherConfigurator));
        vm.prank(owner);
        oracle.setPauseConfigurator(address(otherConfigurator));
        assertEq(address(oracle.pauseConfigurator()), address(otherConfigurator));
    }

    function test_setPauseConfigurator_NewConfiguratorIsUsed() public {
        otherConfigurator.setPaused(true);
        vm.prank(owner);
        oracle.setPauseConfigurator(address(otherConfigurator));
        vm.expectRevert(abi.encodeWithSelector(ICorporatePauseChecker.CorporatePaused.selector));
        oracle.exposed_price();
    }

    function test_RevertWhen_setPauseConfigurator_CallerNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oracle.setPauseConfigurator(address(otherConfigurator));
    }

    function test_RevertWhen_setPauseConfigurator_ZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ICorporatePauseChecker.PauseConfiguratorZeroAddress.selector));
        oracle.setPauseConfigurator(address(0));
    }

    function test_RevertWhen_setPauseConfigurator_EqualCurrent() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(ICorporatePauseChecker.PauseConfiguratorEqualCurrent.selector));
        oracle.setPauseConfigurator(address(configurator));
    }

    function test_setPauseConfigurator_AfterOwnershipTransfer() public {
        address newOwner = makeAddr("newOwner");
        vm.prank(owner);
        oracle.transferOwnership(newOwner);

        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, owner));
        oracle.setPauseConfigurator(address(otherConfigurator));

        vm.prank(newOwner);
        oracle.setPauseConfigurator(address(otherConfigurator));
        assertEq(address(oracle.pauseConfigurator()), address(otherConfigurator));
    }

    function test_exposedSetPauseConfigurator_InternalHasNoAccessControl() public {
        vm.prank(stranger);
        oracle.exposed_setPauseConfigurator(address(otherConfigurator));
        assertEq(address(oracle.pauseConfigurator()), address(otherConfigurator));
    }

    function testFuzz_setPauseConfigurator(address _configurator) public {
        vm.prank(owner);
        if (_configurator == address(0)) {
            vm.expectRevert(abi.encodeWithSelector(ICorporatePauseChecker.PauseConfiguratorZeroAddress.selector));
        } else if (_configurator == address(configurator)) {
            vm.expectRevert(abi.encodeWithSelector(ICorporatePauseChecker.PauseConfiguratorEqualCurrent.selector));
        } else {
            vm.expectEmit(address(oracle));
            emit ICorporatePauseChecker.PauseConfiguratorSet(_configurator);
        }
        oracle.setPauseConfigurator(_configurator);
        assertEq(
            address(oracle.pauseConfigurator()), _configurator == address(0) ? address(configurator) : _configurator
        );
    }

    // ------------------------------------------------------------------ _beforeRead

    function test_beforeRead_NotPaused() public view {
        oracle.exposed_beforeRead();
        assertEq(oracle.exposed_price(), 120e8);
    }

    function test_RevertWhen_beforeRead_Paused() public {
        configurator.setPaused(true);
        vm.expectRevert(abi.encodeWithSelector(ICorporatePauseChecker.CorporatePaused.selector));
        oracle.exposed_beforeRead();
    }

    function test_beforeRead_Unpaused() public {
        configurator.setPaused(true);
        configurator.setPaused(false);
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_ConfiguratorReverts() public {
        configurator.setShouldRevert(true);
        vm.expectRevert(abi.encodeWithSelector(MockPauseConfigurator.MockPauseConfiguratorReverted.selector));
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_price_PausedBlocksFeedRead() public {
        configurator.setPaused(true);
        vm.expectCall(address(feed), abi.encodeCall(MockAggregator.latestRoundData, ()), 0);
        vm.expectRevert(abi.encodeWithSelector(ICorporatePauseChecker.CorporatePaused.selector));
        oracle.exposed_price();
    }

    function test_RevertWhen_price_PausedTakesPrecedenceOverZeroPrice() public {
        configurator.setPaused(true);
        feed.setAnswer(0, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(ICorporatePauseChecker.CorporatePaused.selector));
        oracle.exposed_price();
    }

    // ------------------------------------------------------------------ ownership

    function test_RevertWhen_transferOwnership_CallerNotOwner() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oracle.transferOwnership(stranger);
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, stranger));
        oracle.renounceOwnership();
        assertEq(oracle.owner(), owner);
    }

    // ------------------------------------------------------------------ misconfigured / adversarial configurator

    function test_RevertWhen_beforeRead_ConfiguratorHasNoCode() public {
        // _setPauseConfigurator does not check for code: an EOA is accepted and blocks every read.
        address eoa = makeAddr("eoa");
        vm.prank(owner);
        oracle.setPauseConfigurator(eoa);
        assertEq(address(oracle.pauseConfigurator()), eoa);
        vm.expectRevert(bytes(""));
        oracle.exposed_price();

        // The owner can recover by setting a working configurator.
        vm.prank(owner);
        oracle.setPauseConfigurator(address(otherConfigurator));
        assertEq(oracle.exposed_price(), 120e8);
    }

    function test_RevertWhen_beforeRead_ConfiguratorReturnsNonBool() public {
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(MockRawResponder.Mode.Return, abi.encode(uint256(2)));
        vm.prank(owner);
        oracle.setPauseConfigurator(address(raw));
        vm.expectRevert(bytes(""));
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_ConfiguratorReturnsNoData() public {
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(MockRawResponder.Mode.Return, "");
        vm.prank(owner);
        oracle.setPauseConfigurator(address(raw));
        vm.expectRevert(bytes(""));
        oracle.exposed_beforeRead();
    }

    function test_beforeRead_ConfiguratorReturnsCanonicalBool() public {
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(MockRawResponder.Mode.Return, abi.encode(true));
        vm.prank(owner);
        oracle.setPauseConfigurator(address(raw));
        vm.expectRevert(abi.encodeWithSelector(ICorporatePauseChecker.CorporatePaused.selector));
        oracle.exposed_beforeRead();
        raw.setResponse(MockRawResponder.Mode.Return, abi.encode(false));
        oracle.exposed_beforeRead();
    }

    function test_RevertWhen_beforeRead_ConfiguratorBubblesRawRevertData() public {
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(MockRawResponder.Mode.Revert, abi.encodeWithSignature("Error(string)", "provider down"));
        vm.prank(owner);
        oracle.setPauseConfigurator(address(raw));
        vm.expectRevert(bytes("provider down"));
        oracle.exposed_price();
    }

    /// @dev The read path is `view`, so the configurator is called with STATICCALL: it cannot change state
    ///      or re-enter the oracle with a state change. A configurator that tries makes the read revert.
    function test_RevertWhen_beforeRead_ConfiguratorTriesToWriteState() public {
        StateChangingPauseConfigurator writer = new StateChangingPauseConfigurator();
        vm.prank(owner);
        oracle.setPauseConfigurator(address(writer));
        vm.expectRevert(bytes(""));
        oracle.exposed_price();
        assertEq(writer.calls(), 0);
    }

    function test_RevertWhen_beforeRead_ConfiguratorBurnsAllGas() public {
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(MockRawResponder.Mode.BurnGas, "");
        vm.prank(owner);
        oracle.setPauseConfigurator(address(raw));
        // The callee runs out of gas; the oracle keeps 1/64 of the gas and reverts without data.
        vm.expectRevert(bytes(""));
        oracle.exposed_price{gas: 1_000_000}();
    }
}
