// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


import { IPauseConfigurator } from "./interfaces/IPauseConfigurator.sol";
import { IOracleRegistry } from "./interfaces/ICoinbaseOracleRegistry.sol";

/// @title CoinbasePauseConfigurator
/// @author Robert29000
/// @notice Pause configurator for Coinbase tokenized stocks. It forwards the per-token oracle pause flag
///         of the Coinbase oracle registry.
/// @dev `isPaused()` returns the `paused` value of `oracleRegistry.getOracleParams(token)`. The `multiplier`
///      value is not used.
///      Trust assumption: the Coinbase registry and the operator that sets its pause flags are trusted.
contract CoinbasePauseConfigurator is IPauseConfigurator {

    /// @notice The oracle registry address given to the constructor is the zero address.
    error OracleRegistryZeroAddress();
    /// @notice The token address given to the constructor is the zero address.
    error TokenZeroAddress();

    /// @dev The Coinbase oracle registry that stores the per-token pause flags.
    IOracleRegistry immutable oracleRegistry;
    /// @dev The Coinbase tokenized-stock token whose pause flag is read.
    address immutable token;

    /// @notice Sets the Coinbase registry and the token to read.
    /// @dev Reverts with `OracleRegistryZeroAddress` or `TokenZeroAddress` if an address is zero.
    /// @param _oracleRegistry Address of the Coinbase `IOracleRegistry`.
    /// @param _token Address of the tokenized-stock token.
    constructor(address _oracleRegistry, address _token) {
        require(_oracleRegistry != address(0), OracleRegistryZeroAddress());
        require(_token != address(0), TokenZeroAddress());

        oracleRegistry = IOracleRegistry(_oracleRegistry);
        token = _token;
    }

    /// @inheritdoc IPauseConfigurator
    /// @dev Returns the `paused` value of `oracleRegistry.getOracleParams(token)`.
    function isPaused() external view returns (bool) {
        (, bool paused) = oracleRegistry.getOracleParams(token);
        return paused;
    }

}