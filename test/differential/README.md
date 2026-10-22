# Differential tests: Solidity date/time code vs Python

These tests compare the Solidity date and time code with an independent reference in
[`reference.py`](./reference.py). The reference uses only Python's standard library (`datetime`, `calendar`,
`zoneinfo("America/New_York")`). The code under test is:

- `src/libraries/UnixTimestamp.sol` and `src/libraries/ETTimestamp.sol`.
- The weekend helpers of `src/modules/StalenessChecker.sol`.
- The holiday rules of `src/modules/StalenessCheckerWithHolidays.sol`.

There are two harnesses. Both use the same reference:

| Harness | Folder | Runs the Solidity in | Driver | Files |
|---|---|---|---|---|
| Foundry + ffi | [`solidity/`](./solidity) | Foundry's EVM (revm) | `forge test` fuzzing. Each case calls `ffi_reference.py` | `DifferentialBase.sol`, `*.t.sol`, `ffi_reference.py` |
| Python + py-evm | [`python/`](./python) | titanoboa's in-process py-evm | `pytest` + `hypothesis` | `conftest.py`, `test_*.py`, `requirements.txt` |

```
test/differential/
├── README.md
├── reference.py          # shared Python reference model (standard library only)
├── solidity/             # Foundry + ffi harness
│   ├── DifferentialBase.sol
│   ├── ETTimestampDifferential.t.sol
│   ├── StalenessCheckerWithHolidaysDifferential.t.sol
│   ├── UnixTimestampDifferential.t.sol
│   └── ffi_reference.py
└── python/               # pytest + titanoboa (py-evm) harness
    ├── conftest.py
    ├── requirements.txt
    ├── test_et_timestamp.py
    ├── test_staleness_with_holidays.py
    └── test_unix_timestamp.py
```

Both harnesses call the wrapper contracts in `test/mocks/wrappers/` (`UnixTimestampWrapper`,
`ETTimestampWrapper`, `StalenessCheckerWrapper`, `StalenessCheckerWithHolidaysWrapper`), which expose the internal
functions as external calls.

## What is compared

- **UnixTimestamp:** `getDate`, `getWeekday` and `isWeekendDay`. They are compared over the whole
  `uint256` domain. Past year 9999 the reference subtracts whole 400-year Gregorian cycles. There are
  also explicit edge cases: the epoch, leap days, the 2100 and 2400 century rules, year boundaries,
  `9999-12-31 23:59:59` and `type(uint256).max`.
- **`getTimestamp`:** every result, and the exact `InvalidYear`, `InvalidMonth` or `InvalidDay`
  revert.
- **Leap years:** every year from 1970 to 9999 is checked through `getTimestamp` and `getDate`.
- **ETTimestamp:** `getETTransitionBoundariesInUTC`, `getETOffset`, `toETTimestamp`, `isETWeekend`
  and `adjustedUTCForETOffset`.
- **ET to UTC (`toUTCTimestamp`):** the tests compare the result for both allowed year arguments. These are the ET
  year of the input and the UTC year of the result. The two DST transition hours are skipped (see below). A separate test checks that
  20:00 ET of every day is never skipped.
- **StalenessChecker weekend helpers:** `_isETWeekendTrading` (with a grace period of zero and with a
  random grace period) and `_getLastETFridayCloseTimestampInUTC`.
- ETTimestamp and the weekend helpers are compared against zoneinfo from 2007 to 9999. The tests target the DST switches, the
  Friday 20:00 close and the Sunday 20:00 reopen.
- **StalenessCheckerWithHolidays:** each case sets random holidays in a 28-day window that starts on a Monday. At one
  timestamp, the tests compare `_isETWeekendTrading`, `_isETHolidayTrading`, `_getLastETCloseTimestampInUTC` (while the
  market is closed) and the `_afterRead` result for several prices. Two of these prices are exactly `tradingStaleness`
  before the last close and one second older. The reference (`is_market_closed`, `last_market_close`,
  `holiday_staleness_outcome`) does not copy the contract algorithm. It finds the last trading day before the current
  session with Python dates. The windows cover 2007 to 9963, the DST switches, and 20:00 ET of random days. The
  Python harness also checks the NYSE holidays of 2024 to 2026.

## Known and expected differences and skipped cases

- **DST years before 2007:** ETTimestamp always applies the US DST rule that started in 2007. The
  tz database uses the older rules before that year. This difference is checked explicitly in
  `test_known_divergence_before_2007` and `test_diff_KnownDivergence_Pre2007Rules`.
- **DST transition hours in ET to UTC:** the tests do not compare `toUTCTimestamp` in two hours of each year:
  - The second Sunday of March from 02:00 to 02:59 ET. This hour does not exist.
  - The first Sunday of November from 01:00 to 01:59 ET. This hour occurs twice.

  The contracts never convert these hours, because they convert only 20:00 ET. `reference.et_to_utc` marks
  these hours as not valid, and `test_reference_et_to_utc_skips_two_hours_per_year` checks that it skips exactly
  these two hours.

## Running

Run all commands from the repository root.

### 1. Foundry fuzz tests with ffi

`ffi` is enabled only in the `differential` profile in `foundry.toml`. In the default profile these
tests are skipped.

```sh
FOUNDRY_PROFILE=differential forge test                              # 1000 runs per fuzz test, ~60 s
FOUNDRY_PROFILE=differential FOUNDRY_FUZZ_RUNS=10000 forge test      # deeper run
DIFF_PYTHON=.venv/bin/python FOUNDRY_PROFILE=differential forge test # choose the interpreter
```

`ffi_reference.py` uses only the standard library and works with any `python3` (3.9 or later).

### 2. Python harness (titanoboa / py-evm + hypothesis)

```sh
python3 -m venv .venv
.venv/bin/pip install -r test/differential/python/requirements.txt
.venv/bin/python -m pytest test/differential/python                                # ~3 min
HYPOTHESIS_PROFILE=thorough .venv/bin/python -m pytest test/differential/python    # 5000 examples per property
DIFF_EXHAUSTIVE=1 .venv/bin/python -m pytest test/differential/python              # + every day 1970-2400, every DST year, hourly 2024-2026, all NYSE holidays 2024-2026
```

`conftest.py` first runs `FOUNDRY_PROFILE=differential forge build`. This writes the build to
`out-differential/`, compiled for `evm_version = cancun`, because py-evm does not support Osaka.
It then deploys `UnixTimestampWrapper`, `ETTimestampWrapper`, `StalenessCheckerWrapper` and
`StalenessCheckerWithHolidaysWrapper` from `test/mocks/wrappers/` and calls them with raw ABI calldata. The holiday tests
deploy a new `StalenessCheckerWithHolidaysWrapper` for each case and set its holidays as the owner.

- Set `DIFF_SKIP_BUILD=1` to reuse an existing build.
- Set `FORGE=/path/to/forge` if `forge` is not on your `PATH`.

## Why titanoboa

titanoboa's `boa.env.deploy_code` and `boa.env.execute_code` run any EVM bytecode in-process, so it
works with Foundry's solc output and needs no solc install in Python. Calls take about 1.3 ms. The
other options considered:

- **web3.py + eth-tester + py-solc-x:** this would work too, but it needs a second solc toolchain
  and has more moving parts for the same py-evm backend.
- **ffi only:** this is still provided. It covers the default Foundry EVM, but every fuzz case
  starts a new Python process, which takes about 20 ms per case.
