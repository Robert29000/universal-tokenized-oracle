"""Differential tests: compiled ETTimestamp.sol (via ETTimestampWrapper in py-evm) and the StalenessChecker weekend
helpers (via StalenessCheckerWrapper) vs zoneinfo("America/New_York").

The library hard-codes the post-2007 US DST rule (second Sunday of March 02:00 -> first Sunday of
November 02:00), so the comparison domain starts in 2007. DST boundaries passed to the per-timestamp
functions come from getETTransitionBoundariesInUTC(<UTC year of ts>), exactly like StalenessChecker.
"""

from __future__ import annotations

import calendar
from datetime import datetime, time, timedelta, timezone

import pytest
from conftest import EXHAUSTIVE
from hypothesis import given
from hypothesis import strategies as st

import reference as ref

U = "uint256"
FROM = calendar.timegm((2007, 1, 8, 0, 0, 0))  # first Monday of 2007 (needs a Saturday before it)
TO = calendar.timegm((9999, 12, 25, 0, 0, 0))  # reference needs a week of datetime headroom
GRACES = [0, 1, 30 * 60, 4 * 3600, 4 * 3600 + 1, 5 * 3600]


# --------------------------------------------------------------------------- helpers


def sol_boundaries(et, year):
    return tuple(et.call("getETTransitionBoundariesInUTC(uint256)", [U], [year], [U, U]))


def assert_et_functions(et, staleness, ts, grace):
    year = ref.get_date(ts)[0]
    s, e = sol_boundaries(et, year)
    args3 = [ts, s, e]
    ctx = (ts, grace, datetime.fromtimestamp(ts, tz=ref.NEW_YORK).isoformat())

    assert et.call("getETOffset(uint256,uint256,uint256)", [U] * 3, args3, [U]) == ref.et_offset(ts), ctx
    assert et.call("toETTimestamp(uint256,uint256,uint256)", [U] * 3, args3, [U]) == ref.to_et_timestamp(ts), ctx
    assert et.call("isETWeekend(uint256,uint256,uint256)", [U] * 3, args3, ["bool"]) == ref.is_et_weekend(ts), ctx
    assert staleness.call(
        "exposed_isETWeekendTrading(uint256,uint256,uint256,uint256)", [U] * 4, [ts, s, e, 0], ["bool"]
    ) == ref.is_et_weekend_trading(ts, 0), ctx
    assert staleness.call(
        "exposed_isETWeekendTrading(uint256,uint256,uint256,uint256)", [U] * 4, [ts, s, e, grace], ["bool"]
    ) == ref.is_et_weekend_trading(ts, grace), ctx
    assert staleness.call(
        "exposed_getLastETFridayCloseTimestampInUTC(uint256,uint256,uint256)", [U] * 3, args3, [U]
    ) == ref.last_friday_close(ts), ctx
    assert et.call("adjustedUTCForETOffset(uint256,uint256,uint256)", [U] * 3, args3, [U]) == (
        ref.adjusted_utc_for_et_offset(ts)
    ), ctx


# --------------------------------------------------------------------------- DST boundaries


@pytest.mark.parametrize("year", [2007, 2015, 2020, 2024, 2025, 2026, 2027, 2038, 2100, 2400, 9998, 9999])
def test_dst_boundaries_edge_years(et, year):
    assert sol_boundaries(et, year) == ref.dst_boundaries(year)


@given(st.integers(2007, 9999))
def test_dst_boundaries_random_years(et, year):
    assert sol_boundaries(et, year) == ref.dst_boundaries(year)


def test_dst_boundaries_2007_to_2500(et):
    for year in range(2007, 2501):
        assert sol_boundaries(et, year) == ref.dst_boundaries(year), year


@pytest.mark.skipif(not EXHAUSTIVE, reason="set DIFF_EXHAUSTIVE=1")
def test_dst_boundaries_every_year(et):
    for year in range(2007, 10_000):
        assert sol_boundaries(et, year) == ref.dst_boundaries(year), year


def test_known_divergence_before_2007(et):
    """Documented, intentional: zoneinfo applies the pre-2007 US rule, the library does not."""
    assert sol_boundaries(et, 2006) != ref.dst_boundaries(2006)
    assert ref.dst_boundaries(2006) == (1_143_961_200, 1_162_101_600)  # Apr 2 / Oct 29
    assert sol_boundaries(et, 2006) == (1_142_146_800, 1_162_706_400)  # Mar 12 / Nov 5


# --------------------------------------------------------------------------- per-timestamp ET functions


EDGE_TIMESTAMPS = [
    1_710_053_999,  # 2024-03-10 06:59:59 UTC, last EST second
    1_710_054_000,  # first EDT second
    1_730_613_599,  # 2024-11-03 05:59:59 UTC, last EDT second
    1_730_613_600,  # first EST second
    1_717_804_799,  # Fri 19:59:59 EDT
    1_717_804_800,  # Fri 20:00:00 EDT (close == Sat 00:00 UTC)
    1_717_977_599,  # Sun 19:59:59 EDT
    1_717_977_600,  # Sun 20:00:00 EDT (reopen)
    1_717_992_000,  # Mon 00:00 EDT
    1_705_107_599,  # Fri 19:59:59 EST
    1_705_107_600,  # Fri 20:00:00 EST (close == Sat 01:00 UTC)
    1_705_105_800,  # Sat 00:30 UTC == Fri 19:30 EST
    1_704_067_200,  # 2024-01-01 00:00 UTC (still 2023 in New York)
    1_640_998_800,  # Fri 2021-12-31 20:00 EST close == 2022-01-01 01:00 UTC
    1_772_953_200,  # 2026-03-08 07:00 UTC (Mar 1 2026 is a Sunday)
    FROM,
    TO,
]


@pytest.mark.parametrize("grace", GRACES)
@pytest.mark.parametrize("ts", EDGE_TIMESTAMPS)
def test_et_functions_edge_cases(et, staleness, ts, grace):
    assert_et_functions(et, staleness, ts, grace)


@given(st.integers(FROM, TO), st.integers(0, 86_400))
def test_et_functions_full_domain(et, staleness, ts, grace):
    assert_et_functions(et, staleness, ts, grace)


@given(st.integers(calendar.timegm((2015, 1, 1, 0, 0, 0)), calendar.timegm((2100, 1, 1, 0, 0, 0))), st.sampled_from(GRACES))
def test_et_functions_realistic_range(et, staleness, ts, grace):
    assert_et_functions(et, staleness, ts, grace)


@given(st.integers(2007, 9998), st.booleans(), st.integers(-36 * 3600, 36 * 3600), st.sampled_from(GRACES))
def test_et_functions_around_dst_switch(et, staleness, year, at_end, delta, grace):
    s, e = ref.dst_boundaries(year)
    assert_et_functions(et, staleness, (e if at_end else s) + delta, grace)


@given(st.integers(0, 400_000), st.booleans(), st.integers(-3 * 3600, 3 * 3600), st.sampled_from(GRACES))
def test_et_functions_around_close_and_reopen(et, staleness, week, sunday, delta, grace):
    first_close = int(datetime(2007, 1, 12, 20, tzinfo=ref.NEW_YORK).timestamp())  # a Friday close
    pivot = first_close + week * 7 * 86_400 + (2 * 86_400 if sunday else 0)
    assert_et_functions(et, staleness, pivot + delta, grace)


def _boundary_years():
    return sorted({*range(2007, 2500, 13), *range(2024, 2031), 2038, 2100, 2400, 9998})


@pytest.mark.parametrize("year", _boundary_years())
def test_et_functions_exact_dst_switch_seconds(et, staleness, year):
    """Exactly -1s / 0 / +1s around both DST switches (computed by zoneinfo, not by the library)."""
    for pivot in ref.dst_boundaries(year):
        for delta in (-1, 0, 1):
            assert_et_functions(et, staleness, pivot + delta, 30 * 60)


@pytest.mark.parametrize("year", _boundary_years())
def test_et_functions_exact_close_reopen_seconds(et, staleness, year):
    """+-1s around the Friday 20:00 close and Sunday 20:00 reopen of the DST weekends and a mid-summer and a
    New Year weekend of `year`, plus the last/first second of each reopen grace period."""
    starts, ends = ref.dst_boundaries(year)
    pivots = [starts, ends, int(datetime(year, 7, 1, tzinfo=timezone.utc).timestamp())]
    if year < 9999:
        pivots.append(int(datetime(year, 12, 31, 12, tzinfo=timezone.utc).timestamp()))
    for pivot in pivots:
        close = ref.last_friday_close(pivot + 3 * 86_400)
        reopen = int(datetime.combine(
            datetime.fromtimestamp(close, tz=ref.NEW_YORK).date() + timedelta(days=2), time(20, 0), tzinfo=ref.NEW_YORK
        ).timestamp())
        for ts in (close - 1, close, close + 1, reopen - 1, reopen, reopen + 1):
            assert_et_functions(et, staleness, ts, 0)
        for grace in GRACES[1:]:
            for ts in (reopen + grace - 1, reopen + grace):
                assert_et_functions(et, staleness, ts, grace)


def _hourly(start: tuple, end: tuple):
    return range(calendar.timegm((*start, 0, 0, 0)), calendar.timegm((*end, 0, 0, 0)), 3600)


def test_every_hour_around_2024_dst_switches(et, staleness):
    """Hourly sweep over the weeks around both 2024 DST switches (grace 30 min)."""
    for window in (_hourly((2024, 2, 25), (2024, 3, 25)), _hourly((2024, 10, 20), (2024, 11, 20))):
        for ts in window:
            assert_et_functions(et, staleness, ts, 30 * 60)


@pytest.mark.skipif(not EXHAUSTIVE, reason="set DIFF_EXHAUSTIVE=1 (~5 min)")
def test_every_hour_of_2024_to_2026(et, staleness):
    """Hourly sweep over three full years, including both DST switches of each year (grace 30 min)."""
    for ts in _hourly((2024, 1, 1), (2027, 1, 1)):
        assert_et_functions(et, staleness, ts, 30 * 60)


def test_reference_sanity():
    """The reference itself agrees with well-known facts (guards against a broken oracle)."""
    assert ref.dst_boundaries(2024) == (
        int(datetime(2024, 3, 10, 7, tzinfo=timezone.utc).timestamp()),
        int(datetime(2024, 11, 3, 6, tzinfo=timezone.utc).timestamp()),
    )
    assert ref.last_friday_close(1_717_804_800) == 1_717_804_800
    assert ref.is_et_weekend_trading(1_717_804_800) is True
    assert ref.is_et_weekend_trading(1_717_977_600) is False
