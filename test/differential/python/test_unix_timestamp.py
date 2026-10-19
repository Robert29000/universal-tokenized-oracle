"""Differential tests: compiled UnixTimestamp.sol (via UnixTimestampWrapper in py-evm) vs Python datetime."""

from __future__ import annotations

import calendar
from datetime import date

import pytest
from conftest import EXHAUSTIVE, SolidityRevert, selector
from hypothesis import example, given
from hypothesis import strategies as st

import reference as ref

U = "uint256"
DAY = ref.DAY
INVALID_YEAR = selector("InvalidYear()")
INVALID_MONTH = selector("InvalidMonth()")
INVALID_DAY = selector("InvalidDay()")
ERROR_FOR_STATUS = {ref.INVALID_YEAR: INVALID_YEAR, ref.INVALID_MONTH: INVALID_MONTH, ref.INVALID_DAY: INVALID_DAY}

EDGE_TIMESTAMPS = [
    0,
    DAY - 1,
    DAY,
    31_535_999,  # 1970-12-31 23:59:59
    31_536_000,  # 1971-01-01
    68_169_600,  # 1972-02-29
    951_782_400,  # 2000-02-29
    951_868_800,  # 2000-03-01
    1_704_067_199,  # 2023-12-31 23:59:59
    1_704_067_200,  # 2024-01-01
    1_709_164_800,  # 2024-02-29
    2**31 - 1,  # 2038-01-19
    4_107_456_000,  # 2100-02-28
    4_107_542_400,  # 2100-03-01
    2**32 - 1,  # 2106-02-07
    13_574_563_200,  # 2400-02-29
    ref.MAX_DATETIME_TS - DAY + 1,  # 9999-12-31 00:00:00
    ref.MAX_DATETIME_TS,  # 9999-12-31 23:59:59
    ref.MAX_DATETIME_TS + 1,  # 10000-01-01
    2**64 - 1,
    2**128 - 1,
    2**255,
    ref.UINT256_MAX - 1,
    ref.UINT256_MAX,
]


# --------------------------------------------------------------------------- helpers


def sol_get_date(unix, ts):
    return tuple(unix.call("getDate(uint256)", [U], [ts], [U, U, U]))


def sol_weekday(unix, ts):
    return unix.call("getWeekday(uint256)", [U], [ts], [U])


def sol_is_weekend(unix, ts):
    return unix.call("isWeekendDay(uint256)", [U], [ts], ["bool"])


def sol_get_timestamp(unix, y, m, d):
    return unix.call("getTimestamp(uint256,uint256,uint256)", [U, U, U], [y, m, d], [U])


def assert_date_functions(unix, ts):
    assert sol_get_date(unix, ts) == ref.get_date(ts), ts
    assert sol_weekday(unix, ts) == ref.get_weekday(ts), ts
    assert sol_is_weekend(unix, ts) == ref.is_weekend_day(ts), ts


def assert_get_timestamp(unix, y, m, d):
    status, expected = ref.get_timestamp(y, m, d)
    if status in ERROR_FOR_STATUS:
        with pytest.raises(SolidityRevert) as err:
            sol_get_timestamp(unix, y, m, d)
        assert err.value.selector == ERROR_FOR_STATUS[status], (y, m, d)
    else:
        assert sol_get_timestamp(unix, y, m, d) == expected, (y, m, d)


# --------------------------------------------------------------------------- getDate / getWeekday / isWeekendDay


@pytest.mark.parametrize("ts", EDGE_TIMESTAMPS)
def test_date_functions_edge_cases(unix, ts):
    assert_date_functions(unix, ts)


@given(st.integers(min_value=0, max_value=ref.UINT256_MAX))
@example(0)
@example(ref.MAX_DATETIME_TS + 1)
@example(ref.UINT256_MAX)
def test_date_functions_full_uint256_domain(unix, ts):
    assert_date_functions(unix, ts)


@given(st.integers(min_value=0, max_value=ref.MAX_DATETIME_TS))
def test_date_functions_datetime_range(unix, ts):
    assert_date_functions(unix, ts)


@given(st.integers(min_value=0, max_value=ref.MAX_DATETIME_TS // DAY), st.sampled_from([0, 1, DAY // 2, DAY - 1]))
def test_date_functions_day_borders(unix, day, second):
    assert_date_functions(unix, day * DAY + second)


def test_leap_years_every_year(unix):
    """For every supported year, Feb 28 + 1 day is Feb 29 exactly when Python says it is a leap year."""
    for year in range(1970, 10_000):
        feb28 = sol_get_timestamp(unix, year, 2, 28)
        _, month, day = sol_get_date(unix, feb28 + DAY)
        assert (month, day) == ((2, 29) if calendar.isleap(year) else (3, 1)), year


def test_year_boundaries_every_year(unix):
    """Jan 1 00:00 of every supported year, and the second before it."""
    for year in range(1970, 10_000):
        ts = calendar.timegm((year, 1, 1, 0, 0, 0))
        assert sol_get_timestamp(unix, year, 1, 1) == ts, year
        assert sol_get_date(unix, ts) == (year, 1, 1), year
        if ts:
            assert sol_get_date(unix, ts - 1) == (year - 1, 12, 31), year


@pytest.mark.skipif(not EXHAUSTIVE, reason="set DIFF_EXHAUSTIVE=1 (~4 min)")
def test_every_day_1970_to_2400(unix):
    end = calendar.timegm((2400, 12, 31, 0, 0, 0)) // DAY
    for day in range(end + 1):
        ts = day * DAY
        assert sol_get_date(unix, ts) == ref.get_date(ts), ts
        assert sol_weekday(unix, ts) == ref.get_weekday(ts), ts


# --------------------------------------------------------------------------- getTimestamp


@pytest.mark.parametrize(
    "y,m,d",
    [
        (1970, 1, 1),
        (1970, 12, 31),
        (1972, 2, 29),
        (2000, 2, 29),
        (2024, 2, 29),
        (2100, 2, 28),
        (2100, 3, 1),
        (2400, 2, 29),
        (9999, 12, 31),
        (1969, 12, 31),
        (10_000, 1, 1),
        (0, 0, 0),
        (2024, 0, 1),
        (2024, 13, 1),
        (2024, 1, 0),
        (2024, 1, 32),
        (ref.UINT256_MAX, 1, 1),
        (2024, ref.UINT256_MAX, 1),
        (2024, 1, ref.UINT256_MAX),
    ],
)
def test_get_timestamp_edge_cases(unix, y, m, d):
    assert_get_timestamp(unix, y, m, d)


@given(st.integers(1960, 10_010), st.integers(0, 13), st.integers(0, 32))
def test_get_timestamp_bounded_domain(unix, y, m, d):
    assert_get_timestamp(unix, y, m, d)


@given(st.dates(min_value=date(1970, 1, 1)))
def test_get_timestamp_valid_dates_round_trip(unix, dt):
    ts = sol_get_timestamp(unix, dt.year, dt.month, dt.day)
    assert ts == calendar.timegm(dt.timetuple())
    assert sol_get_date(unix, ts) == (dt.year, dt.month, dt.day)


@given(
    st.integers(0, ref.UINT256_MAX),
    st.integers(0, ref.UINT256_MAX),
    st.integers(0, ref.UINT256_MAX),
)
def test_get_timestamp_unbounded(unix, y, m, d):
    assert_get_timestamp(unix, y, m, d)


NONEXISTENT = [(2023, 2, 29), (2023, 2, 30), (2024, 2, 30), (2023, 2, 31), (2100, 2, 29), (2024, 4, 31), (2024, 11, 31)]


@pytest.mark.parametrize("y,m,d", NONEXISTENT)
def test_get_timestamp_rejects_nonexistent_dates(unix, y, m, d):
    assert ref.get_timestamp(y, m, d) == (ref.INVALID_DAY, 0)
    with pytest.raises(SolidityRevert) as err:
        sol_get_timestamp(unix, y, m, d)
    assert err.value.selector == INVALID_DAY

