"""Differential tests: compiled TransitionCheckerWithHolidays (via TransitionCheckerWithHolidaysWrapper in py-evm) vs the
market model in reference.py (transition_outcome).

The reference model is built on zoneinfo("America/New_York") and Python dates. It does not copy the contract
algorithm: on the New York date D it finds the 04:00, 09:30 and 16:00 transitions if D is a trading day, and the
20:00 transition if D + 1 is a trading day. It checks D and the day before, in real UTC instants.
For each case it compares the `_afterRead` result at one timestamp: accepted, or the error of the transition.
"""

from __future__ import annotations

import calendar
from datetime import date, datetime, time, timedelta, timezone

import boa
import pytest
from conftest import EXHAUSTIVE, SolidityRevert, deploy_transition_with_holidays, selector
from hypothesis import given
from hypothesis import strategies as st
from test_staleness_with_holidays import FIRST_MONDAY, HOLIDAYS_UNDER_TEST, LAST_WEEK, NYSE_HOLIDAYS, window_holidays

import reference as ref

ROUND = "(uint80,int256,uint256,uint256,uint80)"
MAX_WINDOW = 4 * 3600
WINDOWS = [0, 1, 10 * 60, MAX_WINDOW - 1]  # default windows of the NYSE tests

OUTCOME_SELECTORS = {
    selector("TransitionOvernightToPreMarket()"): 1,
    selector("TransitionPreMarketToRegular()"): 2,
    selector("TransitionRegularToPostMarket()"): 3,
    selector("TransitionPostMarketToOvernight()"): 4,
}


# --------------------------------------------------------------------------- helpers


def sol_outcome(c, ts: int) -> int:
    boa.env.timestamp = ts
    try:
        c.call(f"exposed_afterRead({ROUND})", [ROUND], [(1, 1, 0, ts, 1)], [])
    except SolidityRevert as e:
        assert e.selector in OUTCOME_SELECTORS, f"unexpected revert 0x{e.data.hex()}"
        return OUTCOME_SELECTORS[e.selector]
    return ref.TRANSITION_OK


def assert_transition(c, holidays, windows, ts: int):
    ctx = (ts, datetime.fromtimestamp(ts, tz=ref.NEW_YORK).isoformat(), windows, sorted(holidays))
    assert sol_outcome(c, ts) == ref.transition_outcome(ts, holidays, windows), ctx


def deploy(holidays, default_window: int, own_windows: dict[int, int]):
    """The oracle and the window in force for each transition."""
    c = deploy_transition_with_holidays(holidays, default_window, own_windows)
    return c, tuple(own_windows.get(i, default_window) for i in range(4))


def boundary(d: date, transition: int) -> int:
    return int(datetime.combine(d, ref.TRANSITION_TIMES[transition], tzinfo=ref.NEW_YORK).timestamp())


windows_st = st.integers(0, MAX_WINDOW - 1)
# About one transition in two has its own window. The own window is often short or zero.
own_windows_st = st.dictionaries(st.integers(0, 3), st.one_of(st.integers(0, 2), windows_st), max_size=4)
seeds = st.integers(0, 2**84 - 1)


# --------------------------------------------------------------------------- random holidays and windows


@given(st.integers(0, LAST_WEEK), seeds, st.booleans(), windows_st, own_windows_st, st.integers(0, 14 * 86_400))
def test_random_holidays(_build, week, seed, sparse, default_window, own_windows, offset):
    first_day = FIRST_MONDAY + week * 7 * 86_400
    holidays = window_holidays(first_day, seed, sparse)
    c, windows = deploy(holidays, default_window, own_windows)
    assert_transition(c, holidays, windows, first_day + 7 * 86_400 + offset)


@given(
    st.integers(0, LAST_WEEK), seeds, st.booleans(), windows_st, own_windows_st,
    st.integers(7, 20), st.integers(0, 3), st.integers(-2, MAX_WINDOW + 2),
)
def test_random_holidays_around_boundary(_build, week, seed, sparse, default_window, own_windows, day, transition, delta):
    """From 2 seconds before a boundary of a random date to 2 seconds after the longest window."""
    first_day = FIRST_MONDAY + week * 7 * 86_400
    holidays = window_holidays(first_day, seed, sparse)
    c, windows = deploy(holidays, default_window, own_windows)
    d = datetime.fromtimestamp(first_day + day * 86_400, tz=timezone.utc).date()
    assert_transition(c, holidays, windows, boundary(d, transition) + delta)


@given(st.integers(2007, 9998), st.booleans(), seeds, st.booleans(), windows_st, own_windows_st,
       st.integers(-5 * 86_400, 5 * 86_400))
def test_random_holidays_around_dst_switch(_build, year, at_end, seed, sparse, default_window, own_windows, delta):
    pivot = ref.dst_boundaries(year)[1 if at_end else 0]
    first_day = pivot - pivot % 86_400 - 13 * 86_400  # the Monday two weeks before the switch (a Sunday)
    holidays = window_holidays(first_day, seed, sparse)
    c, windows = deploy(holidays, default_window, own_windows)
    assert_transition(c, holidays, windows, pivot + delta)


# --------------------------------------------------------------------------- NYSE calendar 2024-2026


@pytest.fixture(scope="module")
def nyse(_build):
    return {w: deploy(NYSE_HOLIDAYS, w, {}) for w in WINDOWS}


@pytest.mark.parametrize("window", WINDOWS)
@pytest.mark.parametrize("holiday", HOLIDAYS_UNDER_TEST, ids=str)
def test_nyse_holiday_edges(nyse, holiday, window):
    """The day before, the day of and the day after each holiday: every boundary at -1, +0, +1, +window and
    +window + 1 seconds."""
    c, windows = nyse[window]
    for d in (holiday - timedelta(days=1), holiday, holiday + timedelta(days=1)):
        for i in range(4):
            b = boundary(d, i)
            for ts in (b - 1, b, b + 1, b + windows[i], b + windows[i] + 1):
                assert_transition(c, NYSE_HOLIDAYS, windows, ts)


def test_nyse_every_boundary_of_2024_to_2026(nyse):
    """+1 second and the last second of the window after every boundary of every day (10-minute window)."""
    c, windows = nyse[10 * 60]
    d = date(2024, 1, 1)
    while d < date(2027, 1, 1):
        for i in range(4):
            b = boundary(d, i)
            for ts in (b + 1, b + windows[i]):
                assert_transition(c, NYSE_HOLIDAYS, windows, ts)
        d += timedelta(days=1)


@pytest.mark.skipif(not EXHAUSTIVE, reason="set DIFF_EXHAUSTIVE=1 (~25 min)")
def test_nyse_every_10_minutes_of_2024_to_2026(nyse):
    c, windows = nyse[MAX_WINDOW - 1]
    for ts in range(calendar.timegm((2024, 1, 1, 0, 0, 0)), calendar.timegm((2027, 1, 1, 0, 0, 0)), 600):
        assert_transition(c, NYSE_HOLIDAYS, windows, ts + 1)


# --------------------------------------------------------------------------- reference sanity


def test_reference_sanity():
    """The reference itself agrees with well-known facts (guards against a broken oracle)."""
    w = (600, 600, 600, 600)
    thanksgiving = frozenset({date(2024, 11, 28)})
    wed_2000 = int(datetime(2024, 11, 27, 20, tzinfo=ref.NEW_YORK).timestamp())
    thu_0930 = int(datetime(2024, 11, 28, 9, 30, tzinfo=ref.NEW_YORK).timestamp())
    thu_2000 = int(datetime(2024, 11, 28, 20, tzinfo=ref.NEW_YORK).timestamp())
    assert ref.transition_outcome(wed_2000 + 1, frozenset(), w) == 4
    assert ref.transition_outcome(wed_2000 + 1, thanksgiving, w) == ref.TRANSITION_OK  # closes for the holiday
    assert ref.transition_outcome(thu_0930 + 1, thanksgiving, w) == ref.TRANSITION_OK  # no session on the holiday
    assert ref.transition_outcome(thu_2000 + 1, thanksgiving, w) == 4  # reopen on the holiday
    assert ref.transition_outcome(thu_0930 + 1, frozenset(), w) == 2
    # The boundary itself is not in the window, the last second of the window is.
    assert ref.transition_outcome(thu_0930, frozenset(), w) == ref.TRANSITION_OK
    assert ref.transition_outcome(thu_0930 + 600, frozenset(), w) == 2
    assert ref.transition_outcome(thu_0930 + 601, frozenset(), w) == ref.TRANSITION_OK
    # Friday 20:00 is the weekly close, Sunday 20:00 the weekly reopen.
    fri_2000 = int(datetime(2024, 6, 7, 20, tzinfo=ref.NEW_YORK).timestamp())
    sun_2000 = int(datetime(2024, 6, 9, 20, tzinfo=ref.NEW_YORK).timestamp())
    assert ref.transition_outcome(fri_2000 + 1, frozenset(), w) == ref.TRANSITION_OK
    assert ref.transition_outcome(sun_2000 + 1, frozenset(), w) == 4
    # A window that crosses 00:00 ET is still found from the next date (the contract caps windows below 4 hours).
    long_window = (0, 0, 0, 6 * 3600)
    assert ref.transition_outcome(wed_2000 - 86_400 + 5 * 3600, frozenset(), long_window) == 4  # Wed 01:00 ET
    assert datetime.fromtimestamp(wed_2000, tz=timezone.utc) == datetime(2024, 11, 28, 1, tzinfo=timezone.utc)
    assert time(20, 0) == ref.TRANSITION_TIMES[ref.POST_MARKET_TO_OVERNIGHT]
