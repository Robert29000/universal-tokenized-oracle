// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {UnixTimestamp} from "./UnixTimestamp.sol";
import {ETTimestamp} from "./ETTimestamp.sol";

/// @title ETHelpers
/// @author Robert29000
/// @notice Shared US Eastern Time (ET) helpers for the oracle modules.
/// @dev The modules call these helpers instead of their own internal copies. If two modules declare the same
///      non-virtual internal function, a contract that inherits both modules does not compile (Error 6480).
///      Thus a helper that more than one module needs goes in this library.
library ETHelpers {

    /// @notice Returns the US daylight saving time boundaries for the UTC year of a timestamp.
    /// @dev Uses the UTC calendar year of `_timestamp`. Close to New Year the ET date can be in the
    ///      previous year, but both dates are in standard time, so the result is the same.
    ///      Reverts with `UnixTimestamp.InvalidYear` if the UTC year of `_timestamp` is greater than 9999.
    /// @param _timestamp Unix timestamp in seconds (UTC).
    /// @return Unix timestamp (UTC) when daylight saving time starts (second Sunday of March, 07:00 UTC).
    /// @return Unix timestamp (UTC) when daylight saving time ends (first Sunday of November, 06:00 UTC).
    function getDSTBoundaries(uint256 _timestamp) internal pure returns (uint256, uint256) {
        (uint256 year, ,) = UnixTimestamp.getDate(_timestamp);

        return ETTimestamp.getETTransitionBoundariesInUTC(year);
    }

}
