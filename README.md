# Universal Tokenized Oracle

Universal Tokenized Oracle is a price oracle for tokenized stocks. It reads the price from a Chainlink-compatible feed. Before it returns the price, it runs a set of checks. If one check fails, the read reverts.

The checks are in separate modules. Each module overrides one of two hooks in `UniversalOracleBase`:

1. `_beforeRead()` runs before the oracle reads the feed. Checks that do not need the round data go here, for example the L2 sequencer status and the corporate pause.
2. `_afterRead(round)` runs after the oracle reads the feed. Checks on the round data go here, for example price > 0 and staleness.


The project supports the tokenized stocks of these providers:

- Robinhood
- Coinbase
- xStocks (Backed Finance)

## Modules

| Module | Hook | Description |
|---|---|---|
| `UniversalOracleBase` | both | Base contract. Reads `latestRoundData()` from the feed and runs the hooks. Reverts if the price is 0 or less. The deployer becomes the owner. |
| `L2SequencerChecker` | `_beforeRead` | Reverts while the L2 sequencer is down. After the sequencer status changes, it also reverts until `downtimeWait` seconds pass. Reads the Chainlink L2 sequencer uptime feed. |
| `StalenessChecker` | `_afterRead` | Reverts if the price is older than `maxStaleness`. While the market trades, it reverts if the price is older than `tradingStaleness`. During the weekend closure (Friday 20:00 ET to Sunday 20:00 ET), it accepts a price that was fresh at the Friday close. A grace period `reopenTimeWait` applies after the Sunday reopen. |
| `StalenessCheckerWithHolidays` | `_afterRead` | Extends `StalenessChecker` with US market holidays. The owner sets each holiday date. On a holiday, the module accepts a price that was fresh at the last market close. |
| `CorporatePauseChecker` | `_beforeRead` | Reverts while the corporate provider reports a pause. Reads an `IPauseConfigurator`. The owner can replace the configurator. |
| `RobinhoodPauseConfigurator` | n/a | `IPauseConfigurator` for Robinhood. Returns the oracle pause flag of the Robinhood contract. |
| `CoinbasePauseConfigurator` | n/a | `IPauseConfigurator` for Coinbase. Returns the per-token `paused` flag of the Coinbase oracle registry. |
| `xStocksPauseConfigurator` | n/a | `IPauseConfigurator` for xStocks. Reports a pause during a time window before and after each multiplier update of the token (for example a stock split). The owner sets the window length. |

The modules use these libraries:

| Library | Description |
|---|---|
| `UnixTimestamp` | Converts Unix timestamps to Gregorian calendar dates and back. Returns the weekday. |
| `ETTimestamp` | US Eastern Time helpers. Calculates the daylight saving time (DST) boundaries and the ET offset, and converts UTC to ET and back. Uses the US DST rules in force since 2007. |

For the security issues that the project accepts, see [`doc/KNOWN_ISSUES.md`](./doc/KNOWN_ISSUES.md).

## Build

### Requirements

- [Foundry](https://book.getfoundry.sh/getting-started/installation)
- Git
- Python 3.9 or later. You need Python only for the differential tests.

### Install the dependencies

The dependencies are Git submodules in `lib/`: `forge-std`, `chainlink-evm` and `openzeppelin-contracts`.

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

The contracts are abstract modules. The repository has no deployment script. To use the oracle, write a contract that inherits the modules that you need, and expose `_price()`.

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

The differential tests compare `UnixTimestamp`, `ETTimestamp` and the weekend helpers of `StalenessChecker` with a reference in Python. There is also a second harness that uses `pytest`, `hypothesis` and titanoboa. For the setup, the commands and the known differences, see [`test/differential/README.md`](./test/differential/README.md).

## TO-DO

- Process half days in the holiday module (`StalenessCheckerWithHolidays`).
- Add a fallback oracle.
- Do gas optimizations across the contracts.
