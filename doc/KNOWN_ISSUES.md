# Known Issues

This file lists the issues that the project knows about and accepts. Each issue gives the reason why the project does not change the code.


| ID | Title | Module | Status |
|---|---|---|---|
| [KI-1](#ki-1-the-oracle-accepts-the-pre-pause-round-after-an-unpause) | The oracle accepts the pre-pause round after an unpause | `CorporatePauseChecker` | Acknowledged |
| [KI-2](#ki-2-the-sequencer-check-accepts-a-round-with-startedat-of-zero) | The sequencer check accepts a round with `startedAt` of zero | `L2SequencerChecker` | Acknowledged |
| [KI-3](#ki-3-the-xstocks-pause-ends-before-the-feed-reports-a-new-price) | The xStocks pause ends before the feed reports a new price | `xStocksPauseConfigurator` | Acknowledged |
| [KI-4](#ki-4-a-pending-update-hides-the-pause-window-of-the-last-activation) | A pending update hides the pause window of the last activation | `xStocksPauseConfigurator` | Acknowledged |
| [KI-5](#ki-5-the-smoothed-price-is-not-a-classic-exponential-moving-average) | The smoothed price is not a classic exponential moving average | `TransitionEMAWithHolidays` | Acknowledged |
| [KI-6](#ki-6-the-search-for-the-previous-price-reads-only-the-current-phase-of-the-proxy) | The search for the previous price reads only the current phase of the proxy | `TransitionEMAWithHolidays` | Acknowledged |

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

## KI-5: The smoothed price is not a classic exponential moving average

**Location:** `TransitionEMAWithHolidays._applyEMA`

**Description:** The module does not calculate a classic exponential moving average (EMA). A classic EMA uses each price update of the feed and keeps the last average in storage. The module uses only two prices:

- The answer of the latest round.
- The answer of the last round that the feed updated at or before the boundary of the transition.

The module ignores the rounds between these two rounds. Thus a price in the window has an effect on the result only while it is the latest price.

In the window, the weight of the price before the boundary decreases from almost 1 to `exp(-1)`, about 0.368. After the last second of the window, the module returns the latest price. Thus at the end of the window, the returned price can change by about 36.8% of the difference between the two prices in one second.

**Status:** Acknowledged.

**Reason:** The module is a smoothing function for the transition window. It is not a price average. A classic EMA must write its value to storage at each price update. The oracle reads the price in `view` functions, so it cannot write to storage. To calculate an EMA from the round history, the module must read each round in the window. This increases the gas cost of each read in the window. The module reads at most `ceil(log2(n + 1))` rounds, with `n` the aggregator round id of the latest round. Set the transition windows so that the step at the end of the window is acceptable for the consumers.

## KI-6: The search for the previous price reads only the current phase of the proxy

**Location:** `TransitionEMAWithHolidays._getLastPriceBeforeTransition`

**Description:** A Chainlink proxy starts a new phase each time it changes its aggregator. The module searches for the previous price only in the rounds of the current phase. If the proxy started the current phase after the boundary of the transition, no round of the current phase is before the boundary. In this case, the module returns the latest price and does not smooth it.

**Status:** Acknowledged.

**Reason:** The project does not search the previous phases, for two reasons:

- Gas: a search in a previous phase needs more calls to the proxy and to the aggregator of that phase.
- Access control: the binary search must know the last round id of the phase. The proxy does not return the last round id of a previous phase. The module must read it from the aggregator of the phase. An aggregator can have access control, so the read can revert.

A change of aggregator does not occur frequently. If it occurs in a transition window, the module returns the latest price, as an oracle without this module does.
