"""Independent Python reference model for src/libraries/{UnixTimestamp,ETTimestamp}.sol.

Everything here is derived from the Python standard library (datetime, calendar, zoneinfo),
never from the Solidity algorithms, so it can act as a differential-testing oracle.

Used by:
  * solidity/ffi_reference.py -> Foundry `vm.ffi` differential fuzz tests (solidity/*.t.sol)
  * python/test_*.py          -> pytest / hypothesis harness that runs the compiled Solidity in py-evm
"""

from __future__ import annotations

import calendar
from datetime import date, datetime, time, timedelta, timezone
from zoneinfo import ZoneInfo

DAY = 86_400
# Gregorian calendar repeats every 400 years = 146_097 days (which is also a whole number of weeks).
GREGORIAN_CYCLE_DAYS = 146_097
GREGORIAN_CYCLE_YEARS = 400

# Largest timestamp Python's datetime can represent: 9999-12-31 23:59:59 UTC.
MAX_DATETIME_TS = 253_402_300_799
UINT256_MAX = 2**256 - 1

NEW_YORK = ZoneInfo("America/New_York")
# The current US DST rule (Energy Policy Act of 2005) applies from 2007 on. Earlier years used
# different rules in the tz database, which the Solidity library intentionally does not model.
FIRST_YEAR_CURRENT_DST_RULE = 2007

# Error codes for get_timestamp (mirrors UnixTimestamp's custom errors)
OK = 0
INVALID_YEAR = 1
INVALID_MONTH = 2
INVALID_DAY = 3  # day is 0 or greater than the number of days in the month

MONDAY, FRIDAY, SATURDAY, SUNDAY = 0, 4, 5, 6


# --------------------------------------------------------------------------- UnixTimestamp


def _date_for_days(days_since_epoch: int) -> tuple[date, int]:
    """Return (date within datetime's range, extra_years) for an arbitrarily large day count.

    Python's `date` stops at year 9999, so larger day counts are reduced by whole 400-year
    Gregorian cycles; the caller adds `extra_years` back to the year.
    """
    cycles = 0
    if days_since_epoch > (date(9999, 12, 31) - date(1970, 1, 1)).days:
        cycles = days_since_epoch // GREGORIAN_CYCLE_DAYS
        days_since_epoch -= cycles * GREGORIAN_CYCLE_DAYS
    return date(1970, 1, 1) + timedelta(days=days_since_epoch), cycles * GREGORIAN_CYCLE_YEARS


def get_date(ts: int) -> tuple[int, int, int]:
    """UTC (year, month, day) for any uint256 timestamp."""
    if ts <= MAX_DATETIME_TS:
        d = datetime.fromtimestamp(ts, tz=timezone.utc)
        return d.year, d.month, d.day
    d, extra_years = _date_for_days(ts // DAY)
    return d.year + extra_years, d.month, d.day


def get_weekday(ts: int) -> int:
    """Monday = 0 ... Sunday = 6, for any uint256 timestamp."""
    if ts <= MAX_DATETIME_TS:
        return datetime.fromtimestamp(ts, tz=timezone.utc).weekday()
    d, _ = _date_for_days(ts // DAY)  # 146_097 days is a whole number of weeks
    return d.weekday()


def is_weekend_day(ts: int) -> bool:
    return get_weekday(ts) in (SATURDAY, SUNDAY)


def is_leap_year(year: int) -> bool:
    return calendar.isleap(year)


def get_timestamp(year: int, month: int, day: int) -> tuple[int, int]:
    """Return (status, timestamp).

    The library's domain is 1970 <= year <= 9999, 1 <= month <= 12 and 1 <= day <= days in the month.
    A non-existent date (e.g. 2023-02-30) returns INVALID_DAY, like the Solidity library.
    """
    if not 1970 <= year <= 9999:
        return INVALID_YEAR, 0
    if not 1 <= month <= 12:
        return INVALID_MONTH, 0
    if not 1 <= day <= calendar.monthrange(year, month)[1]:
        return INVALID_DAY, 0
    return OK, calendar.timegm(datetime(year, month, day, tzinfo=timezone.utc).timetuple())


# --------------------------------------------------------------------------- ETTimestamp


def _utc_offset_seconds(ts: int) -> int:
    off = datetime.fromtimestamp(ts, tz=NEW_YORK).utcoffset()
    assert off is not None
    return int(off.total_seconds())


def _find_transition(lo: int, hi: int) -> int:
    """First UTC second in (lo, hi] whose New York UTC offset differs from the one at lo."""
    base = _utc_offset_seconds(lo)
    assert _utc_offset_seconds(hi) != base, "no transition in range"
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if _utc_offset_seconds(mid) == base:
            lo = mid
        else:
            hi = mid
    return hi


def dst_boundaries(year: int) -> tuple[int, int]:
    """(DST start, DST end) in UTC for `year`, found by scanning zoneinfo's America/New_York offsets."""
    utc = timezone.utc
    start = _find_transition(
        int(datetime(year, 3, 1, tzinfo=utc).timestamp()), int(datetime(year, 5, 1, tzinfo=utc).timestamp())
    )
    end = _find_transition(
        int(datetime(year, 10, 1, tzinfo=utc).timestamp()), int(datetime(year, 11, 15, tzinfo=utc).timestamp())
    )
    return start, end


def et_offset(ts: int) -> int:
    """Hours behind UTC, as a positive number of seconds (EST = 18000, EDT = 14400)."""
    return -_utc_offset_seconds(ts)


def to_et_timestamp(ts: int) -> int:
    """New York wall-clock time re-encoded as if it were UTC seconds."""
    return ts - et_offset(ts)


def is_et_weekend(ts: int) -> bool:
    return datetime.fromtimestamp(ts, tz=NEW_YORK).weekday() in (SATURDAY, SUNDAY)


def _most_recent_local(ts: int, weekday: int, at: time) -> int:
    """UTC timestamp of the most recent `weekday` at local New York time `at`, at or before ts."""
    local = datetime.fromtimestamp(ts, tz=NEW_YORK)
    back = (local.weekday() - weekday) % 7
    candidate_day = local.date() - timedelta(days=back)
    candidate = datetime.combine(candidate_day, at, tzinfo=NEW_YORK)
    if int(candidate.timestamp()) > ts:
        candidate = datetime.combine(candidate_day - timedelta(days=7), at, tzinfo=NEW_YORK)
    return int(candidate.timestamp())


def last_friday_close(ts: int) -> int:
    """UTC timestamp of the most recent Friday 20:00 New York time at or before ts."""
    return _most_recent_local(ts, FRIDAY, time(20, 0))


def is_et_weekend_trading(ts: int, grace: int = 0) -> bool:
    """True while the (24/5) market is closed: Fri 20:00 -> Sun 20:00 ET, plus `grace` seconds after."""
    local = datetime.fromtimestamp(ts, tz=NEW_YORK)
    wd, t = local.weekday(), local.time()
    closed = (wd == FRIDAY and t >= time(20, 0)) or wd == SATURDAY or (wd == SUNDAY and t < time(20, 0))
    if closed:
        return True
    since_reopen = ts - _most_recent_local(ts, SUNDAY, time(20, 0))
    return since_reopen < grace


def adjusted_utc_for_et_offset(ts: int) -> int:
    """ts + 1h when New York is on standard time, else ts (Friday 20:00 ET close expressed in UTC)."""
    return ts + 3600 if et_offset(ts) == 5 * 3600 else ts


def et_to_utc(et_ts: int) -> tuple[bool, int]:
    """(valid, UTC timestamp) of the New York wall-clock time encoded in `et_ts` (see to_et_timestamp).

    `valid` is False in the two DST transition hours: the March hour that does not exist and the November
    hour that occurs twice. zoneinfo gives two different offsets for fold=0 and fold=1 only in these hours.
    The oracle never converts these hours (market closes and reopens are at 20:00 ET), so the differential
    tests skip them.
    """
    wall = datetime(1970, 1, 1) + timedelta(seconds=et_ts)
    first, second = wall.replace(tzinfo=NEW_YORK, fold=0), wall.replace(tzinfo=NEW_YORK, fold=1)
    if first.utcoffset() != second.utcoffset():
        return False, 0
    return True, int(first.timestamp())


# --------------------------------------------------------------------------- StalenessCheckerWithHolidays

# Market model: 24/5 trading. The session of weekday D runs from 20:00 ET on the day before D to 20:00 ET on D.
MARKET_CLOSE = time(20, 0)

# Outcome codes of StalenessCheckerWithHolidays._afterRead
OUTCOME_OK = 0
OUTCOME_MAX_STALENESS = 1
OUTCOME_TRADING_STALENESS = 2

DAY_REGULAR, DAY_HOLIDAY, DAY_WEEKEND = 0, 1, 2  # IStalenessCheckerWithHolidays.DayType


def holidays_from_mask(first_day_ts: int, mask: int, days: int = 28) -> frozenset[date]:
    """Weekdays `first_day + i` for every set bit i of `mask` (weekend bits are ignored, like setHolidayET)."""
    first = datetime.fromtimestamp(first_day_ts, tz=timezone.utc).date()
    out = {first + timedelta(days=i) for i in range(days) if mask >> i & 1}
    return frozenset(d for d in out if d.weekday() < SATURDAY)


def _is_trading_day(d: date, holidays: frozenset[date]) -> bool:
    return d.weekday() < SATURDAY and d not in holidays


def _session_date(local: datetime) -> date:
    """The weekday session that contains `local` (it can be a weekend day or a holiday)."""
    return local.date() + timedelta(days=1) if local.time() >= MARKET_CLOSE else local.date()


def day_type(ts: int, holidays: frozenset[date]) -> tuple[int, int, int, int]:
    """(year, month, day, DayType) of the New York calendar date of ts."""
    d = datetime.fromtimestamp(ts, tz=NEW_YORK).date()
    kind = DAY_WEEKEND if d.weekday() >= SATURDAY else DAY_HOLIDAY if d in holidays else DAY_REGULAR
    return d.year, d.month, d.day, kind


def is_et_holiday_trading(ts: int, holidays: frozenset[date], grace: int) -> bool:
    """True while the session of ts is a holiday, or less than `grace` seconds after 20:00 ET on a holiday."""
    local = datetime.fromtimestamp(ts, tz=NEW_YORK)
    if _session_date(local) in holidays:
        return True
    if local.date() in holidays and local.time() >= MARKET_CLOSE:
        reopen = int(datetime.combine(local.date(), MARKET_CLOSE, tzinfo=NEW_YORK).timestamp())
        return ts - reopen < grace
    return False


def is_market_closed(ts: int, holidays: frozenset[date], grace: int) -> bool:
    """Weekend closure, holiday closure, or a reopen grace period after either."""
    return is_et_weekend_trading(ts, grace) or is_et_holiday_trading(ts, holidays, grace)


def last_market_close(ts: int, holidays: frozenset[date]) -> int:
    """UTC timestamp of 20:00 ET on the last trading day before the session of ts (always <= ts)."""
    d = _session_date(datetime.fromtimestamp(ts, tz=NEW_YORK)) - timedelta(days=1)
    while not _is_trading_day(d, holidays):
        d -= timedelta(days=1)
    return int(datetime.combine(d, MARKET_CLOSE, tzinfo=NEW_YORK).timestamp())


def holiday_staleness_outcome(
    ts: int, updated_at: int, holidays: frozenset[date], max_staleness: int, trading_staleness: int, grace: int
) -> int:
    """Expected result of StalenessCheckerWithHolidays._afterRead at block.timestamp == ts (answer > 0)."""
    if updated_at + max_staleness < ts:
        return OUTCOME_MAX_STALENESS
    if updated_at + trading_staleness >= ts:
        return OUTCOME_OK
    if not is_market_closed(ts, holidays, grace):
        return OUTCOME_TRADING_STALENESS
    if updated_at + trading_staleness < last_market_close(ts, holidays):
        return OUTCOME_TRADING_STALENESS
    return OUTCOME_OK
