#!/usr/bin/env python3
"""CLI wrapper around ../reference.py for Foundry's `vm.ffi`.

Prints a single 0x-prefixed hex string containing the ABI encoding of the results, which
`vm.ffi` hands back to Solidity as raw bytes (decode with abi.decode). Standard library only.

Usage:
  ffi_reference.py date <ts>
      -> (uint256 year, uint256 month, uint256 day, uint256 weekday, bool isWeekendDay)
  ffi_reference.py timestamp <year> <month> <day>
      -> (uint256 status, uint256 timestamp)      status: 0 ok, 1 year, 2 month, 3 day
  ffi_reference.py dst <year>
      -> (uint256 dstStartUTC, uint256 dstEndUTC)
  ffi_reference.py et <ts> <grace>
      -> (uint256 offset, uint256 etTimestamp, bool isETWeekend, bool isETWeekendTrading,
          bool isETWeekendTradingWithGrace, uint256 lastFridayCloseUTC, uint256 adjustedUTC)
      isETWeekendTrading is the StalenessChecker weekend check with grace 0, isETWeekendTradingWithGrace
      the same check with <grace>.
  ffi_reference.py et2utc <etTimestamp>
      -> (bool valid, uint256 utc)    valid is false in the two DST transition hours (not compared)
  ffi_reference.py holiday <ts> <grace> <firstDay> <mask> <maxStaleness> <tradingStaleness> <age>
      -> (bool isETWeekendTrading, bool isETHolidayTrading, bool isMarketClosed,
          uint256 etYear, uint256 etMonth, uint256 etDay, uint256 dayType, uint256 lastClose,
          uint256 outcomeAtAge, uint256 outcomeAtCloseEdge, uint256 outcomeAfterCloseEdge)
      Holidays are the weekdays firstDay + i days for every set bit i of <mask> (28 days).
      Outcomes (0 ok, 1 MaxStalenessReached, 2 TradingStalenessReached) are for updatedAt equal to
      ts - age, lastClose - tradingStaleness and lastClose - tradingStaleness - 1.
"""

from __future__ import annotations

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))  # ../reference.py

import reference as ref  # noqa: E402


def _word(value: int | bool) -> str:
    value = int(value)
    if not 0 <= value <= ref.UINT256_MAX:
        raise ValueError(f"value out of uint256 range: {value}")
    return f"{value:064x}"


def encode(*values: int | bool) -> str:
    return "0x" + "".join(_word(v) for v in values)


def main(argv: list[str]) -> str:
    cmd, args = argv[0], [int(a, 0) for a in argv[1:]]
    if cmd == "date":
        (ts,) = args
        y, m, d = ref.get_date(ts)
        return encode(y, m, d, ref.get_weekday(ts), ref.is_weekend_day(ts))
    if cmd == "timestamp":
        status, ts = ref.get_timestamp(*args)
        return encode(status, ts)
    if cmd == "dst":
        (year,) = args
        return encode(*ref.dst_boundaries(year))
    if cmd == "et":
        ts, grace = args
        return encode(
            ref.et_offset(ts),
            ref.to_et_timestamp(ts),
            ref.is_et_weekend(ts),
            ref.is_et_weekend_trading(ts, 0),
            ref.is_et_weekend_trading(ts, grace),
            ref.last_friday_close(ts),
            ref.adjusted_utc_for_et_offset(ts),
        )
    if cmd == "et2utc":
        (et_ts,) = args
        return encode(*ref.et_to_utc(et_ts))
    if cmd == "holiday":
        ts, grace, first_day, mask, max_staleness, trading, age = args
        holidays = ref.holidays_from_mask(first_day, mask)
        close = ref.last_market_close(ts, holidays)

        def outcome(updated_at: int) -> int:
            return ref.holiday_staleness_outcome(ts, updated_at, holidays, max_staleness, trading, grace)

        return encode(
            ref.is_et_weekend_trading(ts, grace),
            ref.is_et_holiday_trading(ts, holidays, grace),
            ref.is_market_closed(ts, holidays, grace),
            *ref.day_type(ts, holidays),
            close,
            outcome(ts - age),
            outcome(close - trading),
            outcome(close - trading - 1),
        )
    raise SystemExit(f"unknown command: {cmd}")


if __name__ == "__main__":
    sys.stdout.write(main(sys.argv[1:]))
