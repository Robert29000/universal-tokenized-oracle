// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {ETHelpers} from "src/libraries/ETHelpers.sol";

/// @notice Exposes every internal ETHelpers library function as an external call.
contract ETHelpersWrapper {
    function getDSTBoundaries(uint256 _timestamp) external pure returns (uint256, uint256) {
        return ETHelpers.getDSTBoundaries(_timestamp);
    }
}
