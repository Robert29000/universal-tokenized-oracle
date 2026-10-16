// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;


import { IPauseConfigurator } from "../interfaces/IPauseConfigurator.sol";
import { IOracleRegistry } from "./interfaces/ICoinbaseOracleRegistry.sol";

contract CoinbasePauseConfigurator is IPauseConfigurator {

    error OracleRegistryZeroAddress();
    error TokenZeroAddress();

    IOracleRegistry immutable oracleRegistry;
    address immutable token;

    constructor(address _oracleRegistry, address _token) {
        require(_oracleRegistry != address(0), OracleRegistryZeroAddress());
        require(_token != address(0), TokenZeroAddress());

        oracleRegistry = IOracleRegistry(_oracleRegistry);
        token = _token;
    }

    function isPaused() external view returns (bool) {
        (, bool paused) = oracleRegistry.getOracleParams(token);
        return paused;
    }

}