// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IOracleRegistry} from "src/modules/corporate_providers/interfaces/ICoinbaseOracleRegistry.sol";

/// @notice Configurable stand-in for Coinbase's IOracleRegistry (per-token multiplier + pause flag).
contract MockCoinbaseOracleRegistry is IOracleRegistry {
    error MockOracleRegistryReverted();

    mapping(address token => uint256) public multiplierOf;
    mapping(address token => bool) public pausedOf;
    bool public shouldRevert;

    function setOracleParams(address token, uint256 multiplier, bool paused) external {
        multiplierOf[token] = multiplier;
        pausedOf[token] = paused;
    }

    function setOraclePaused(address token, bool paused) external {
        if (token == address(0)) revert ZeroAddress();
        pausedOf[token] = paused;
        emit OraclePausedSet(token, paused);
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function getOracleParams(address token) external view returns (uint256 multiplier, bool paused) {
        if (shouldRevert) revert MockOracleRegistryReverted();
        return (multiplierOf[token], pausedOf[token]);
    }
}
