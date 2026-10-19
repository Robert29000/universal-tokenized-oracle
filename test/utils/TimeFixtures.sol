// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

/// @notice Reference timestamps (UTC seconds) used across the tests.
/// @dev All values were produced with Python's datetime / zoneinfo("America/New_York"), not with the
///      library under test, so they act as an independent oracle.
library TimeFixtures {
    // ------------------------------------------------------------ US DST boundaries (UTC)
    // 2024: Mar 1 is a Friday, Nov 1 is a Friday
    uint256 internal constant DST_START_2024 = 1710054000; // 2024-03-10 07:00 UTC
    uint256 internal constant DST_END_2024 = 1730613600; // 2024-11-03 06:00 UTC
    // 2025: Mar 1 / Nov 1 are Saturdays
    uint256 internal constant DST_START_2025 = 1741503600; // 2025-03-09 07:00 UTC
    uint256 internal constant DST_END_2025 = 1762063200; // 2025-11-02 06:00 UTC
    // 2026: Mar 1 / Nov 1 are Sundays (the "already Sunday" branches)
    uint256 internal constant DST_START_2026 = 1772953200; // 2026-03-08 07:00 UTC
    uint256 internal constant DST_END_2026 = 1793512800; // 2026-11-01 06:00 UTC
    // 2027: Mar 1 / Nov 1 are Mondays (largest forward adjustment)
    uint256 internal constant DST_START_2027 = 1805007600; // 2027-03-14 07:00 UTC
    uint256 internal constant DST_END_2027 = 1825567200; // 2027-11-07 06:00 UTC
    // 2100 (non-leap century year)
    uint256 internal constant DST_START_2100 = 4108690800; // 2100-03-14 07:00 UTC
    uint256 internal constant DST_END_2100 = 4129250400; // 2100-11-07 06:00 UTC

    // ------------------------------------------------------------ An EDT week (June 2024)
    uint256 internal constant EDT_MON_0000 = 1717387200; // Mon 2024-06-03 00:00 EDT
    uint256 internal constant EDT_FRI_2000 = 1717804800; // Fri 2024-06-07 20:00 EDT (= Sat 00:00 UTC)
    uint256 internal constant EDT_SUN_2000 = 1717977600; // Sun 2024-06-09 20:00 EDT
    uint256 internal constant EDT_NEXT_MON_0000 = 1717992000; // Mon 2024-06-10 00:00 EDT

    // ------------------------------------------------------------ An EST week (January 2024)
    uint256 internal constant EST_MON_0000 = 1704690000; // Mon 2024-01-08 00:00 EST
    uint256 internal constant EST_FRI_2000 = 1705107600; // Fri 2024-01-12 20:00 EST (= Sat 01:00 UTC)
    uint256 internal constant EST_SUN_2000 = 1705280400; // Sun 2024-01-14 20:00 EST
    uint256 internal constant EST_NEXT_MON_0000 = 1705294800; // Mon 2024-01-15 00:00 EST

    // ------------------------------------------------------------ Calendar edge cases (00:00 UTC)
    uint256 internal constant JAN_01_2024 = 1704067200;
    uint256 internal constant FEB_29_2024 = 1709164800;
    uint256 internal constant MAR_01_2024 = 1709251200;
    uint256 internal constant MAR_01_2000 = 951868800;
    uint256 internal constant FEB_28_2100 = 4107456000;
    uint256 internal constant MAR_01_2100 = 4107542400;
    uint256 internal constant DEC_31_9999 = 253402214400;
    uint256 internal constant MAX_DATETIME = 253402300799; // 9999-12-31 23:59:59 UTC (Python datetime max)
}
