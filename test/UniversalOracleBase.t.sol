// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

import {IUniversalOracleBase} from "src/interfaces/IUniversalOracleBase.sol";
import {UniversalOracleBaseWrapper} from "test/mocks/wrappers/UniversalOracleBaseWrapper.sol";
import {MockAggregator} from "test/mocks/MockAggregator.sol";
import {MockRawResponder} from "test/mocks/MockAdversarial.sol";

contract UniversalOracleBaseTest is Test {
    MockAggregator internal feed;
    UniversalOracleBaseWrapper internal oracle;

    address internal deployer = makeAddr("deployer");

    function setUp() public {
        vm.warp(1_750_000_000);
        feed = new MockAggregator(8, "TSLA / USD");
        feed.setAnswer(250e8, block.timestamp);
        vm.prank(deployer);
        oracle = new UniversalOracleBaseWrapper(address(feed));
    }

    // ------------------------------------------------------------------ constructor

    function test_constructor_SetsAggregatorAndOwner() public view {
        assertEq(address(oracle.aggregator()), address(feed));
        assertEq(oracle.owner(), deployer);
    }

    function test_RevertWhen_constructor_AggregatorZeroAddress() public {
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.AggregatorZeroAddress.selector));
        new UniversalOracleBaseWrapper(address(0));
    }

    // ------------------------------------------------------------------ _price

    function test_price_ReturnsAnswer() public view {
        assertEq(oracle.exposed_price(), 250e8);
    }

    function test_price_SmallestPositiveAnswer() public {
        feed.setAnswer(1, block.timestamp);
        assertEq(oracle.exposed_price(), 1);
    }

    function test_price_MaxAnswer() public {
        feed.setAnswer(type(int256).max, block.timestamp);
        assertEq(oracle.exposed_price(), uint256(type(int256).max));
    }

    function test_price_IgnoresRoundMetadata() public {
        // The base contract does not validate roundId / answeredInRound / timestamps.
        feed.setRoundData(0, 7, 0, 0, 0);
        assertEq(oracle.exposed_price(), 7);
    }

    function test_price_CallsLatestRoundDataOnce() public {
        vm.expectCall(address(feed), abi.encodeCall(MockAggregator.latestRoundData, ()), 1);
        oracle.exposed_price();
    }

    function test_RevertWhen_price_AnswerZero() public {
        feed.setAnswer(0, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.PriceZero.selector));
        oracle.exposed_price();
    }

    function test_RevertWhen_price_AnswerNegative() public {
        feed.setAnswer(-1, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.PriceZero.selector));
        oracle.exposed_price();
    }

    function test_RevertWhen_price_AnswerMinInt() public {
        feed.setAnswer(type(int256).min, block.timestamp);
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.PriceZero.selector));
        oracle.exposed_price();
    }

    function test_RevertWhen_price_FeedReverts() public {
        feed.setShouldRevert(true);
        vm.expectRevert(abi.encodeWithSelector(MockAggregator.MockAggregatorReverted.selector));
        oracle.exposed_price();
    }

    function testFuzz_price(int256 _answer) public {
        feed.setAnswer(_answer, block.timestamp);
        if (_answer <= 0) {
            vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.PriceZero.selector));
            oracle.exposed_price();
        } else {
            assertEq(oracle.exposed_price(), uint256(_answer));
        }
    }

    // ------------------------------------------------------------------ hooks

    function test_beforeRead_IsNoOp() public {
        feed.setShouldRevert(true); // base hook must not touch the feed
        oracle.exposed_beforeRead();
    }

    function test_afterRead_AcceptsPositiveAnswer() public view {
        oracle.exposed_afterRead(IUniversalOracleBase.RoundData(1, 1, 0, 0, 1));
    }

    function test_RevertWhen_afterRead_AnswerZero() public {
        vm.expectRevert(abi.encodeWithSelector(IUniversalOracleBase.PriceZero.selector));
        oracle.exposed_afterRead(IUniversalOracleBase.RoundData(1, 0, 0, 0, 1));
    }

    // ------------------------------------------------------------------ decimals / description

    function test_decimals_PassesThrough() public {
        assertEq(oracle.decimals(), 8);
        feed.setDecimals(18);
        assertEq(oracle.decimals(), 18);
    }

    function test_description_IsPrefixed() public {
        assertEq(oracle.description(), "Universal feed: TSLA / USD");
        feed.setDescription("");
        assertEq(oracle.description(), "Universal feed: ");
    }

    function test_RevertWhen_decimals_FeedReverts() public {
        feed.setShouldRevert(true);
        vm.expectRevert(abi.encodeWithSelector(MockAggregator.MockAggregatorReverted.selector));
        oracle.decimals();
    }

    function test_RevertWhen_description_FeedReverts() public {
        feed.setShouldRevert(true);
        vm.expectRevert(abi.encodeWithSelector(MockAggregator.MockAggregatorReverted.selector));
        oracle.description();
    }

    // ------------------------------------------------------------------ misconfigured / malformed feed

    function test_RevertWhen_price_AggregatorHasNoCode() public {
        // Only address(0) is rejected; an EOA aggregator deploys but every read reverts without data.
        UniversalOracleBaseWrapper o = new UniversalOracleBaseWrapper(makeAddr("eoa"));
        vm.expectRevert(bytes(""));
        o.exposed_price();
        vm.expectRevert(bytes(""));
        o.decimals();
    }

    function test_RevertWhen_price_FeedReturnsShortData() public {
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(MockRawResponder.Mode.Return, abi.encode(uint80(1), int256(100))); // 2 of 5 words
        UniversalOracleBaseWrapper o = new UniversalOracleBaseWrapper(address(raw));
        vm.expectRevert(bytes(""));
        o.exposed_price();
    }

    function test_RevertWhen_price_FeedRoundIdOutOfRange() public {
        // roundId is uint80: a word above 2**80 - 1 fails ABI decoding instead of being truncated.
        MockRawResponder raw = new MockRawResponder();
        raw.setResponse(
            MockRawResponder.Mode.Return,
            abi.encode(uint256(1) << 80, int256(100), block.timestamp, block.timestamp, uint256(1))
        );
        UniversalOracleBaseWrapper o = new UniversalOracleBaseWrapper(address(raw));
        vm.expectRevert(bytes(""));
        o.exposed_price();
    }

    /// @notice The price is returned in the feed's own decimals, never rescaled: consumers must read
    ///         `decimals()`. An 18-decimals feed returns an 18-decimals price.
    function test_price_NotRescaledForFeedDecimals() public {
        MockAggregator feed18 = new MockAggregator(18, "TSLA / USD 18");
        feed18.setAnswer(250e18, block.timestamp);
        UniversalOracleBaseWrapper o = new UniversalOracleBaseWrapper(address(feed18));
        assertEq(o.decimals(), 18);
        assertEq(o.exposed_price(), 250e18);
    }
}
