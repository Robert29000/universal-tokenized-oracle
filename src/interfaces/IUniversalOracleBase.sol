// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @title IUniversalOracleBase
/// @author Robert29000
/// @notice Common interface of every universal tokenized-stock oracle: the feed metadata
///         (`decimals`, `description`), the round data shape and the base errors.
interface IUniversalOracleBase {

    /// @notice One round of the underlying Chainlink-compatible aggregator.
    /// @dev Field-by-field copy of the values returned by `latestRoundData()`:
    ///      - `roundId`: id of the round.
    ///      - `answer`: price, scaled by the aggregator `decimals()`. Can be zero or negative in the raw feed.
    ///      - `startedAt`: Unix timestamp (seconds) when the round started.
    ///      - `updatedAt`: Unix timestamp (seconds) of the last answer update.
    ///      - `answeredInRound`: round id in which the answer was computed (deprecated in Chainlink, not checked).
    struct RoundData {
        uint80 roundId;
        int256 answer;
        uint256 startedAt;
        uint256 updatedAt;
        uint80 answeredInRound;
    }

    /// @notice The aggregator address given to the constructor is the zero address.
    error AggregatorZeroAddress();
    /// @notice The aggregator returned an answer that is zero or negative.
    error PriceZero();

    
    /// @notice Returns the number of decimals of the price.
    /// @return The number of decimals of the price.
    function decimals() external view returns (uint8);

    /// @notice Returns a human-readable description of the feed.
    /// @return The feed description.
    function description() external view returns (string memory);
}