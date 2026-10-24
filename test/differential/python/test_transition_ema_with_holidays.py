"""Differential tests: compiled TransitionEMAWithHolidays (via TransitionEMAWithHolidaysWrapper and MockPhaseAggregator
in py-evm) vs the reference in reference.py (transition_window, ema_price_range).

The reference finds the transition window with zoneinfo("America/New_York") and Python dates, finds the previous
price with a linear scan over the rounds, and calculates the exponential with an 80-digit `Decimal`. It does not copy
the contract algorithm. solady's expWad is at most about 1 wei from the exact value, so the reference gives a price
range for alpha - 1 and alpha + 1. For each case the tests push random rounds before and after the boundary and
compare `_price()` with this range.
"""

from __future__ import annotations

import random
from datetime import date, datetime, timedelta, timezone

import boa
import pytest
from conftest import deploy_transition_ema_with_holidays
from hypothesis import given
from hypothesis import strategies as st
from test_staleness_with_holidays import FIRST_MONDAY, HOLIDAYS_UNDER_TEST, LAST_WEEK, NYSE_HOLIDAYS, window_holidays

import reference as ref

U = "uint256"
MAX_WINDOW = 4 * 3600
MAX_PRICE = 10**30
WINDOWS = [1, 10 * 60, MAX_WINDOW - 1]  # default windows of the NYSE tests


# --------------------------------------------------------------------------- helpers


def deploy(holidays, default_window: int, own_windows: dict[int, int]):
    """The oracle, the feed and the window in force for each transition."""
    c, feed = deploy_transition_ema_with_holidays(holidays, default_window, own_windows)
    return c, feed, tuple(own_windows.get(i, default_window) for i in range(4))


def push_rounds(feed, pivot: int, ts: int, rng: random.Random) -> list[tuple[int, int]]:
    """0 to 5 rounds at or before `pivot` and 0 to 3 rounds in (pivot, ts], at least one round in total. The last round
    before `pivot` is at `pivot`, 1 second before, or up to 1 hour before it. Timestamps do not decrease."""
    n_before = rng.randrange(6)
    n_after = rng.randrange(4) if pivot < ts else 0
    if n_before + n_after == 0:
        n_before = 1
    last = pivot - rng.choice([0, 1, rng.randrange(1, 3601)])
    step = rng.randrange(600)
    times = [last - (n_before - 1 - k) * step for k in range(n_before)]
    times += sorted(rng.randrange(pivot + 1, ts + 1) for _ in range(n_after))
    rounds = [(rng.randrange(1, MAX_PRICE + 1), t) for t in times]
    for answer, t in rounds:
        feed.transact("pushRound(int256,uint256)", ["int256", U], [answer, t])
    return rounds


def assert_price(c, feed, holidays, windows, ts: int, seed: int):
    outcome, boundary = ref.transition_window(ts, holidays, windows)
    rounds = push_rounds(feed, boundary if outcome else ts, ts, random.Random(seed))
    lo, hi = ref.ema_price_range(ts, boundary, windows[outcome - 1] if outcome else 1, rounds)
    boa.env.timestamp = ts
    price = c.call("exposed_price()", [], [], [U])
    ctx = (ts, datetime.fromtimestamp(ts, tz=ref.NEW_YORK).isoformat(), windows, sorted(holidays), rounds)
    assert lo <= price <= hi, ctx


def boundary_of(d: date, transition: int) -> int:
    return int(datetime.combine(d, ref.TRANSITION_TIMES[transition], tzinfo=ref.NEW_YORK).timestamp())


windows_st = st.integers(0, MAX_WINDOW - 1)
# About one transition in two has its own window. The own window is often short or zero.
own_windows_st = st.dictionaries(st.integers(0, 3), st.one_of(st.integers(0, 2), windows_st), max_size=4)
seeds = st.integers(0, 2**84 - 1)
round_seeds = st.integers(0, 2**64 - 1)


# --------------------------------------------------------------------------- random holidays, windows and rounds


@given(st.integers(0, LAST_WEEK), seeds, st.booleans(), windows_st, own_windows_st, st.integers(0, 14 * 86_400), round_seeds)
def test_random_holidays(_build, week, seed, sparse, default_window, own_windows, offset, round_seed):
    first_day = FIRST_MONDAY + week * 7 * 86_400
    holidays = window_holidays(first_day, seed, sparse)
    c, feed, windows = deploy(holidays, default_window, own_windows)
    assert_price(c, feed, holidays, windows, first_day + 7 * 86_400 + offset, round_seed)


@given(
    st.integers(0, LAST_WEEK), seeds, st.booleans(), windows_st, own_windows_st,
    st.integers(7, 20), st.integers(0, 3), st.integers(-2, MAX_WINDOW + 2), round_seeds,
)
def test_random_holidays_around_boundary(
    _build, week, seed, sparse, default_window, own_windows, day, transition, delta, round_seed
):
    """From 2 seconds before a boundary of a random date to 2 seconds after the longest window."""
    first_day = FIRST_MONDAY + week * 7 * 86_400
    holidays = window_holidays(first_day, seed, sparse)
    c, feed, windows = deploy(holidays, default_window, own_windows)
    d = datetime.fromtimestamp(first_day + day * 86_400, tz=timezone.utc).date()
    assert_price(c, feed, holidays, windows, boundary_of(d, transition) + delta, round_seed)


@given(st.integers(2007, 9998), st.booleans(), seeds, st.booleans(), windows_st, own_windows_st,
       st.integers(-5 * 86_400, 5 * 86_400), round_seeds)
def test_random_holidays_around_dst_switch(_build, year, at_end, seed, sparse, default_window, own_windows, delta, round_seed):
    pivot = ref.dst_boundaries(year)[1 if at_end else 0]
    first_day = pivot - pivot % 86_400 - 13 * 86_400  # the Monday two weeks before the switch (a Sunday)
    holidays = window_holidays(first_day, seed, sparse)
    c, feed, windows = deploy(holidays, default_window, own_windows)
    assert_price(c, feed, holidays, windows, pivot + delta, round_seed)


# --------------------------------------------------------------------------- NYSE calendar 2024-2026


@pytest.mark.parametrize("window", WINDOWS)
@pytest.mark.parametrize("holiday", HOLIDAYS_UNDER_TEST, ids=str)
def test_nyse_holiday_edges(_build, holiday, window):
    """The day before, the day of and the day after each holiday: every boundary at +1, +window / 2, +window and
    +window + 1 seconds. A new oracle and feed for each timestamp."""
    for d in (holiday - timedelta(days=1), holiday, holiday + timedelta(days=1)):
        for i in range(4):
            b = boundary_of(d, i)
            for k, ts in enumerate((b + 1, b + window // 2 + 1, b + window, b + window + 1)):
                c, feed, windows = deploy(NYSE_HOLIDAYS, window, {})
                assert_price(c, feed, NYSE_HOLIDAYS, windows, ts, d.toordinal() * 16 + i * 4 + k)


# --------------------------------------------------------------------------- reference sanity


def test_reference_sanity():
    """The reference itself agrees with well-known facts (guards against a broken oracle)."""
    assert ref.ema_alpha(0, 600) == ref.WAD
    assert ref.ema_alpha(600, 600) == 367_879_441_171_442_321  # exp(-1)
    assert ref.ema_alpha(300, 600) == 606_530_659_712_633_423  # exp(-0.5)
    w = (600, 600, 600, 600)
    wed_0930 = int(datetime(2024, 6, 5, 9, 30, tzinfo=ref.NEW_YORK).timestamp())
    assert ref.transition_window(wed_0930 + 1, frozenset(), w) == (2, wed_0930)
    assert ref.transition_window(wed_0930 + 601, frozenset(), w) == (ref.TRANSITION_OK, 0)
    prev, latest = 400 * 10**8, 410 * 10**8
    rounds = [(prev, wed_0930), (latest, wed_0930 + 1)]
    assert ref.ema_price_range(wed_0930 + 600, wed_0930, 600, rounds) == (40_632_120_558, 40_632_120_558)
    # Outside a window, no round before the boundary, or the latest round before the boundary: the latest price.
    assert ref.ema_price_range(wed_0930 + 601, 0, 600, rounds) == (latest, latest)
    assert ref.ema_price_range(wed_0930 + 600, wed_0930, 600, [(latest, wed_0930 + 1)]) == (latest, latest)
    assert ref.ema_price_range(wed_0930 + 600, wed_0930 + 1, 600, rounds) == (latest, latest)
