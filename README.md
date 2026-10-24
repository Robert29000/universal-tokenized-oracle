# Universal Tokenized Oracle

> [!WARNING]
> **These contracts are not audited.** The code has unit, fuzz and differential tests, but no independent security
> audit. Do not use it to secure real funds. Use it at your own risk.

Universal Tokenized Oracle is a price oracle for tokenized stocks. It reads the price from a Chainlink-compatible feed. Before it returns the price, it runs a set of checks. If one check fails, the read reverts.

The checks are in separate modules. Each module overrides one or more of these hooks in `UniversalOracleBase`:

1. `_beforeRead()` runs before the oracle reads the feed. Checks that do not need the round data go here.
2. `_afterRead(round)` runs after the oracle reads the feed. Checks on the round data go here.
3. `_adjustAnswer(answer)` runs after the checks and converts the validated answer into the returned price. The base implementation returns the answer unchanged, as a `uint256`.

## Modules

| Module | Description |
|---|---|
| `UniversalOracleBase` | Base contract. Reads `latestRoundData()` from the feed and runs the hooks. Reverts if the price is 0 or less. Returns the price from `_adjustAnswer`. The deployer becomes the owner. |
| `L2SequencerChecker` | Reverts while the L2 sequencer is down. After the sequencer status changes, it also reverts until `downtimeWait` seconds pass. Reads the Chainlink L2 sequencer uptime feed. |
| `StalenessChecker` | Reverts if the price is older than `maxStaleness`. While the market trades, it reverts if the price is older than `tradingStaleness`. During the weekend closure (Friday 20:00 ET to Sunday 20:00 ET), it accepts a price that was fresh at the Friday close. A grace period `reopenTimeWait` applies after the Sunday reopen. |
| `StalenessCheckerWithHolidays` | Extends `StalenessChecker` with US market holidays. The owner sets each holiday date. On a holiday, the module accepts a price that was fresh at the last market close. |
| `TransitionCheckerWithHolidays` | Reverts for a short window after each US market session transition: 04:00 ET (overnight to pre-market), 09:30 ET (pre-market to regular), 16:00 ET (regular to post-market) and 20:00 ET (post-market to overnight). The module skips the transitions that do not occur because of a weekend or a holiday. |
| `CorporatePauseChecker` | Reverts while the corporate provider reports a pause. Reads an `IPauseConfigurator`. The owner can replace the configurator. |

### Providers and configurators

The project supports the tokenized stocks of these providers. Each provider has a different way to report a corporate pause, so each provider has its own `IPauseConfigurator`. `CorporatePauseChecker` reads the configurator of the provider of the token.

| Provider | Configurator | Description |
|---|---|---|
| Robinhood | `RobinhoodPauseConfigurator` | Returns the oracle pause flag of the Robinhood token contract. |
| Coinbase | `CoinbasePauseConfigurator` | Returns the per-token `paused` flag of the Coinbase oracle registry. |
| xStocks (Backed Finance) | `xStocksPauseConfigurator` | Reports a pause during a time window before and after each multiplier update of the token. The owner sets the window length. |

To support a different provider, write a contract that implements `IPauseConfigurator`.

### Shared modules

The modules in `src/modules/shared/` hold state and configuration that more than one module can use. They do not override the hooks. A module that needs them inherits them.

| Shared module | Description |
|---|---|
| `MarketHoliday` | Stores the US market holidays. The owner sets each holiday as an ET calendar date with `setHolidayET`. |
| `TransitionManager` | Stores the windows of the US market session transitions and the ET time of each transition. The owner sets a default window with `setDefaultTransitionWindow` and, optionally, a window for each transition with `setTransitionWindow`. |

If an oracle uses two modules that inherit the same shared module, it has only one copy of its storage, so one call changes both modules.

### Market hours and holidays

`StalenessCheckerWithHolidays` and `TransitionCheckerWithHolidays` use the same market model. The market trades 24 hours a day, 5 days a week. The session of a weekday D starts at 20:00 ET on the day before D and ends at 20:00 ET on D. A holiday on D closes the market for this session. The weekly closure is from Friday 20:00 ET to Sunday 20:00 ET.

Both modules inherit `MarketHoliday`. If an oracle uses both modules, one `setHolidayET` call changes both modules.

`TransitionCheckerWithHolidays` also inherits `TransitionManager`. It has no constructor, so an oracle that uses it calls the `TransitionManager` constructor with the default window. It checks these transitions on the ET date D:

| ET date D | 04:00, 09:30 and 16:00 ET | 20:00 ET |
|---|---|---|
| Trading day (a weekday that is not a holiday) | Checked | Checked if D + 1 is a trading day |
| Holiday | Not checked | Checked if D + 1 is a trading day |
| Sunday | Not checked | Checked if Monday is a trading day |
| Saturday | Not checked | Not checked |

A transition at the boundary B rejects reads for `B < time <= B + window`. The window is the window that the owner set for the transition, or the default window if it is not set.

### Libraries

The modules use these libraries:

| Library | Description |
|---|---|
| `UnixTimestamp` | Converts Unix timestamps to Gregorian calendar dates and back. Returns the weekday. |
| `ETTimestamp` | US Eastern Time helpers. Calculates the daylight saving time (DST) boundaries and the ET offset, and converts UTC to ET and back. Returns whether an ET timestamp or an ET date is on a weekend. Uses the US DST rules in force since 2007. |
| `ETHelpers` | Helpers that more than one module needs. `getDSTBoundaries` returns the DST boundaries for the UTC year of a timestamp. |

For the security issues that the project accepts, see [`doc/KNOWN_ISSUES.md`](./doc/KNOWN_ISSUES.md).

## Build

### Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git
- Python 3.9 or later. You need Python only for the differential tests.

### Install the dependencies

Clone the repository with its submodules:

```sh
git clone --recurse-submodules <repository-url>
```

If you already cloned the repository without the submodules, run this command:

```sh
git submodule update --init --recursive
```

### Compile

```sh
forge build
```

## Tests

Run all commands from the repository root.

```sh
forge test                 # all unit and fuzz tests
forge test -vvv            # show the traces of failed tests
forge test --mt <name>     # run only the tests that match <name>
forge coverage             # coverage report
```

### Test profiles

The profiles are in `foundry.toml`.

| Profile | Command | Description |
|---|---|---|
| `default` | `forge test` | Unit and fuzz tests in `test/`. `ffi` is disabled, so the differential tests are skipped. |
| `differential` | `FOUNDRY_PROFILE=differential forge test` | Differential tests in `test/differential/solidity/`. `ffi` is enabled. Each fuzz test does 1000 runs. The output goes to `out-differential/`, compiled for `evm_version = cancun`. |

The differential tests compare `UnixTimestamp`, `ETTimestamp`, the weekend helpers of `StalenessChecker`, the holiday rules of `StalenessCheckerWithHolidays` and the transition rules of `TransitionCheckerWithHolidays` with a reference in Python. There is also a second harness that uses `pytest`, `hypothesis` and titanoboa. For the setup, the commands and the known differences, see [`test/differential/README.md`](./test/differential/README.md).

## TO-DO

- Process half days in the holiday modules (`StalenessCheckerWithHolidays`, `TransitionCheckerWithHolidays`).
- Add a fallback oracle.
- Do gas optimizations across the contracts.
