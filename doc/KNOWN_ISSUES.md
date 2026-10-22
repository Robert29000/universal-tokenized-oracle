# Known Issues

This file lists the issues that the project knows about and accepts. Each issue gives the reason why the project does not change the code.


| ID | Title | Module | Status |
|---|---|---|---|
| [KI-1](#ki-1-the-oracle-accepts-the-pre-pause-round-after-an-unpause) | The oracle accepts the pre-pause round after an unpause | `CorporatePauseChecker` | Acknowledged |
| [KI-2](#ki-2-the-sequencer-check-accepts-a-round-with-startedat-of-zero) | The sequencer check accepts a round with `startedAt` of zero | `L2SequencerChecker` | Acknowledged |
| [KI-3](#ki-3-the-xstocks-pause-ends-before-the-feed-reports-a-new-price) | The xStocks pause ends before the feed reports a new price | `xStocksPauseConfigurator` | Acknowledged |
| [KI-4](#ki-4-a-pending-update-hides-the-pause-window-of-the-last-activation) | A pending update hides the pause window of the last activation | `xStocksPauseConfigurator` | Acknowledged |

## KI-1: The oracle accepts the pre-pause round after an unpause

**Location:** `CorporatePauseChecker._beforeRead`

**Description:** After the Robinhood or Coinbase operator clears the pause, the oracle accepts the round from before the pause. A consumer can read the old price.

**Status:** Acknowledged.

**Reason:** The provider clears the pause only after it checks that the multiplier update is correct. Then the price is safe to use. The Chainlink documentation describes this process:

- Robinhood: <https://docs.chain.link/data-feeds/tokenized-equity-feeds/robinhood>
- Coinbase: <https://docs.chain.link/data-feeds/tokenized-equity-feeds/coinbase>

## KI-2: The sequencer check accepts a round with `startedAt` of zero

**Location:** `L2SequencerChecker._beforeRead`

**Description:** The function accepts a sequencer round with `startedAt` equal to 0. In this case, the `downtimeWait` grace period does not apply.

**Status:** Acknowledged.

**Reason:** The project plans to deploy the oracle on a chain that already runs, or some time after the chain starts. Thus, the sequencer uptime feed already has a round with a `startedAt` that is not zero.

## KI-3: The xStocks pause ends before the feed reports a new price

**Location:** `xStocksPauseConfigurator.isPaused`

**Description:** The pause ends at `activationTime + pause_window`. If the feed does not report a new price before this time, consumers read the pre-split price. This can occur while the old round is still fresh, or while the market is closed.

**Status:** Acknowledged.

**Reason:** The project assumes that `pause_window` is large enough for all oracles to update their data. Set `pause_window` with the xStocks recommendations: <https://docs.xstocks.fi/developers/multipliers#multiplier-updates>.

## KI-4: A pending update hides the pause window of the last activation

**Location:** `xStocksPauseConfigurator.isPaused`

**Description:** The multiplier updater can schedule a new update soon after an activation. In this case, `isPaused` checks only the pending update. Consumers can read prices inside the pause window of the last activation.

**Status:** Acknowledged.

**Reason:** The project assumes that multiplier updates do not occur frequently. A multiplier update is the result of a corporate action.
