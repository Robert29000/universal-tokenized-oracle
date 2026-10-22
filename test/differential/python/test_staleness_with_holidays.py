"""Differential tests: compiled StalenessCheckerWithHolidays (via StalenessCheckerWithHolidaysWrapper in py-evm) vs the
market model in reference.py (is_market_closed, last_market_close, holiday_staleness_outcome).

The reference model is built on zoneinfo("America/New_York") and Python dates. It does not copy the contract
algorithm: it finds the last trading day before the current session by walking back over calendar dates.
For each case it compares, at one timestamp:
  * `_isETWeekendTrading` and `_isETHolidayTrading`,
  * `_getLastETCloseTimestampInUTC` for the ET date and day type of the timestamp (only while the market is closed),
  * the `_afterRead` result for several prices, including exactly `tradingStaleness` before the last close and one
    second older.
"""

from __future__ import annotations

import calendar
from datetime import date, datetime, time, timedelta, timezone

import boa
import pytest
from conftest import EXHAUSTIVE, SolidityRevert, deploy_staleness_with_holidays, selector
from hypothesis import given
from hypothesis import strategies as st

import reference as ref

U = "uint256"
ROUND = "(uint80,int256,uint256,uint256,uint80)"
MAX = 30 * 86_400
TRADING = 4 * 3600
GRACES = [0, 1, 30 * 60, 4 * 3600 - 1]
WINDOW = 28  # days
FIRST_MONDAY = calendar.timegm((2007, 1, 8, 0, 0, 0))
LAST_WEEK = 415_000  # the window ends in 9963, before the year-9999 limit of getNextDate

OUTCOME_SELECTORS = {
    selector("MaxStalenessReached()"): ref.OUTCOME_MAX_STALENESS,
    selector("TradingStalenessReached()"): ref.OUTCOME_TRADING_STALENESS,
}

# NYSE full-day closures 2024-2026 (early closes are not modelled by the contract)
NYSE_HOLIDAYS = frozenset(
    date(*d)
    for d in [
        (2024, 1, 1), (2024, 1, 15), (2024, 2, 19), (2024, 3, 29), (2024, 5, 27), (2024, 6, 19),
        (2024, 7, 4), (2024, 9, 2), (2024, 11, 28), (2024, 12, 25),
        (2025, 1, 1), (2025, 1, 9), (2025, 1, 20), (2025, 2, 17), (2025, 4, 18), (2025, 5, 26),
        (2025, 6, 19), (2025, 7, 4), (2025, 9, 1), (2025, 11, 27), (2025, 12, 25),
        (2026, 1, 1), (2026, 1, 19), (2026, 2, 16), (2026, 4, 3), (2026, 5, 25), (2026, 6, 19),
        (2026, 7, 3), (2026, 9, 7), (2026, 11, 26), (2026, 12, 25),
    ]
)


# One holiday of each shape for the default run. DIFF_EXHAUSTIVE=1 uses the whole NYSE calendar.
SAMPLE_HOLIDAYS = [
    date(2024, 1, 1),  # Monday, the close before it is in 2023
    date(2024, 2, 19),  # Monday, EST
    date(2024, 3, 29),  # Good Friday, EDT, reopen on Sunday
    date(2024, 11, 28),  # Thanksgiving, Thursday, EST
    date(2025, 1, 1),  # Wednesday, the close before it is in UTC year 2025
    date(2025, 1, 9),  # Thursday, one week after another holiday
    date(2026, 7, 3),  # Friday, EDT
]
HOLIDAYS_UNDER_TEST = sorted(NYSE_HOLIDAYS) if EXHAUSTIVE else SAMPLE_HOLIDAYS


# --------------------------------------------------------------------------- helpers


def sol_outcome(c, ts: int, updated_at: int) -> int:
    boa.env.timestamp = ts
    try:
        c.call(f"exposed_afterRead({ROUND})", [ROUND], [(1, 1, 0, updated_at, 1)], [])
    except SolidityRevert as e:
        assert e.selector in OUTCOME_SELECTORS, f"unexpected revert 0x{e.data.hex()}"
        return OUTCOME_SELECTORS[e.selector]
    return ref.OUTCOME_OK


def assert_holidays(c, holidays, ts: int, grace: int, ages=()):
    s, e = ref.dst_boundaries(ref.get_date(ts)[0])
    ctx = (ts, grace, datetime.fromtimestamp(ts, tz=ref.NEW_YORK).isoformat(), sorted(holidays))

    weekend = c.call("exposed_isETWeekendTrading(uint256,uint256,uint256,uint256)", [U] * 4, [ts, s, e, grace], ["bool"])
    holiday = c.call("exposed_isETHolidayTrading(uint256,uint256,uint256,uint256)", [U] * 4, [ts, s, e, grace], ["bool"])
    assert weekend == ref.is_et_weekend_trading(ts, grace), ctx
    assert holiday == ref.is_et_holiday_trading(ts, holidays, grace), ctx

    close = ref.last_market_close(ts, holidays)
    if ref.is_market_closed(ts, holidays, grace):
        y, m, d, kind = ref.day_type(ts, holidays)
        assert c.call(
            "exposed_getLastETCloseTimestampInUTC(uint256,uint256,uint256,uint8)", [U, U, U, "uint8"], [y, m, d, kind], [U]
        ) == close, ctx

    for updated_at in (close - TRADING, close - TRADING - 1, ts - TRADING - 1, *(ts - a for a in ages)):
        expected = ref.holiday_staleness_outcome(ts, updated_at, holidays, MAX, TRADING, grace)
        assert sol_outcome(c, ts, updated_at) == expected, (*ctx, updated_at)


def window_holidays(first_day: int, seed: int, sparse: bool) -> frozenset[date]:
    mask = seed & (seed >> WINDOW) & (seed >> (2 * WINDOW)) if sparse else seed
    return ref.holidays_from_mask(first_day, mask & ((1 << WINDOW) - 1), WINDOW)


def close_and_reopen(holiday: date) -> tuple[int, int]:
    """(20:00 ET on the last trading day before the holiday, 20:00 ET on the holiday)."""
    reopen = datetime.combine(holiday, time(20, 0), tzinfo=ref.NEW_YORK)
    return ref.last_market_close(int(reopen.timestamp()) - 1, NYSE_HOLIDAYS), int(reopen.timestamp())


seeds = st.integers(0, 2**84 - 1)
graces = st.integers(0, 4 * 3600 - 1)
ages = st.integers(0, MAX + 86_400)


# --------------------------------------------------------------------------- random holidays


@given(st.integers(0, LAST_WEEK), seeds, st.booleans(), st.integers(0, 14 * 86_400), graces, ages)
def test_random_holidays(_build, week, seed, sparse, offset, grace, age):
    first_day = FIRST_MONDAY + week * 7 * 86_400
    holidays = window_holidays(first_day, seed, sparse)
    c = deploy_staleness_with_holidays(holidays, MAX, TRADING, grace)
    assert_holidays(c, holidays, first_day + 7 * 86_400 + offset, grace, [age])


@given(st.integers(0, 4430), seeds, st.booleans(), st.integers(8, 21), st.integers(-3 * 3600, 3 * 3600), graces, ages)
def test_random_holidays_around_close_and_reopen(_build, week, seed, sparse, day, delta, grace, age):
    """Within +-3h of 00:00 UTC (20:00 EDT / 19:00 EST) on a random day of a window in 2015 .. 2100."""
    first_day = calendar.timegm((2015, 1, 5, 0, 0, 0)) + week * 7 * 86_400
    holidays = window_holidays(first_day, seed, sparse)
    c = deploy_staleness_with_holidays(holidays, MAX, TRADING, grace)
    assert_holidays(c, holidays, first_day + day * 86_400 + delta, grace, [age])


@given(st.integers(2007, 9998), st.booleans(), seeds, st.booleans(), st.integers(-5 * 86_400, 5 * 86_400), graces, ages)
def test_random_holidays_around_dst_switch(_build, year, at_end, seed, sparse, delta, grace, age):
    pivot = ref.dst_boundaries(year)[1 if at_end else 0]
    first_day = pivot - pivot % 86_400 - 13 * 86_400  # the Monday two weeks before the switch (a Sunday)
    holidays = window_holidays(first_day, seed, sparse)
    c = deploy_staleness_with_holidays(holidays, MAX, TRADING, grace)
    assert_holidays(c, holidays, pivot + delta, grace, [age])


# --------------------------------------------------------------------------- NYSE calendar 2024-2026


@pytest.fixture(scope="module")
def nyse(_build):
    return {grace: deploy_staleness_with_holidays(NYSE_HOLIDAYS, MAX, TRADING, grace) for grace in GRACES}


@pytest.mark.parametrize("grace", GRACES)
@pytest.mark.parametrize("holiday", HOLIDAYS_UNDER_TEST, ids=str)
def test_nyse_holiday_edges(nyse, holiday, grace):
    """+-1s around the close before each holiday, the reopen on it, and the end of the grace period."""
    close, reopen = close_and_reopen(holiday)
    for ts in (close - 1, close, close + 1, reopen - 1, reopen, reopen + grace - 1, reopen + grace, reopen + grace + 1):
        assert_holidays(nyse[grace], NYSE_HOLIDAYS, ts, grace, [TRADING + 1])


@pytest.mark.parametrize("holiday", HOLIDAYS_UNDER_TEST, ids=str)
def test_nyse_holiday_sweep(nyse, holiday):
    """From 1h before the close before each holiday to 5h after the reopen (grace 30 min): every 2 hours, or every
    30 minutes with DIFF_EXHAUSTIVE=1."""
    close, reopen = close_and_reopen(holiday)
    for ts in range(close - 3600, reopen + 5 * 3600, 1800 if EXHAUSTIVE else 7200):
        assert_holidays(nyse[30 * 60], NYSE_HOLIDAYS, ts, 30 * 60, [TRADING + 1, 86_400])


@pytest.mark.skipif(not EXHAUSTIVE, reason="set DIFF_EXHAUSTIVE=1 (~10 min)")
def test_nyse_every_hour_of_2024_to_2026(nyse):
    for ts in range(calendar.timegm((2024, 1, 1, 0, 0, 0)), calendar.timegm((2027, 1, 1, 0, 0, 0)), 3600):
        assert_holidays(nyse[30 * 60], NYSE_HOLIDAYS, ts, 30 * 60, [TRADING + 1])


# --------------------------------------------------------------------------- reference sanity


def test_reference_sanity():
    """The reference itself agrees with well-known facts (guards against a broken oracle)."""
    thanksgiving = frozenset({date(2024, 11, 28)})
    wed_close = int(datetime(2024, 11, 27, 20, tzinfo=ref.NEW_YORK).timestamp())
    thu_reopen = int(datetime(2024, 11, 28, 20, tzinfo=ref.NEW_YORK).timestamp())
    assert ref.last_market_close(thu_reopen - 1, thanksgiving) == wed_close
    assert ref.is_market_closed(wed_close - 1, thanksgiving, 1800) is False
    assert ref.is_market_closed(wed_close, thanksgiving, 1800) is True
    assert ref.is_market_closed(thu_reopen + 1799, thanksgiving, 1800) is True
    assert ref.is_market_closed(thu_reopen + 1800, thanksgiving, 1800) is False
    # Good Friday: the Saturday read uses the Thursday close.
    good_friday = frozenset({date(2024, 3, 29)})
    saturday = int(datetime(2024, 3, 30, 12, tzinfo=ref.NEW_YORK).timestamp())
    assert ref.last_market_close(saturday, good_friday) == int(datetime(2024, 3, 28, 20, tzinfo=ref.NEW_YORK).timestamp())
    # Without holidays, the last close on a weekend is the Friday close of the weekend helpers.
    assert ref.last_market_close(saturday, frozenset()) == ref.last_friday_close(saturday)
    assert ref.holidays_from_mask(calendar.timegm((2024, 11, 18, 0, 0, 0)), 1 << 10 | 1 << 5) == thanksgiving  # bit 5 = Sat
    assert datetime.fromtimestamp(wed_close, tz=timezone.utc) == datetime(2024, 11, 28, 1, tzinfo=timezone.utc)
    assert timedelta(seconds=thu_reopen - wed_close) == timedelta(days=1)
