# Refreshed offline responsiveness evidence

The current source tree passes the release responsiveness fixture with one warm-up and seven measured samples at each size. Compilation is outside timed regions. Matching checksums were verified against the earlier 1 October snapshot. Raw samples and source-tree fingerprint are in `2026-10-01-responsiveness-refresh.txt`. These measurements cover offline lookup, count, exclusion and inventory-reassignment code paths; they do not measure rendered frame time, real scan/network latency or app memory.

| Items per collection | Operation | Before median (ms) | After median (ms) | Reduction |
| --- | --- | ---: | ---: | ---: |
| 200 | App/source/package lookup pass | 0.271 | 0.251 | 7.7% |
| 200 | One primary update-count read | 0.085 | 0.078 | 8.4% |
| 200 | One exclusion pass over all app keys | 0.018 | 0.017 | 6.1% |
| 200 | Reassign app + Homebrew inventories | 0.446 | 0.388 | 12.9% |
| 2,000 | App/source/package lookup pass | 2.729 | 2.548 | 6.6% |
| 2,000 | One primary update-count read | 0.829 | 0.787 | 5.1% |
| 2,000 | One exclusion pass over all app keys | 0.195 | 0.185 | 5.1% |
| 2,000 | Reassign app + Homebrew inventories | 4.152 | 4.028 | 3.0% |

The medians are lower in this run, but the two snapshots were measured at different times without controlled before/after builds. Differences cannot be causally attributed to recent changes, and no hard regression threshold is established.

The first release build exposed NodeRuntimeReservationTests referencing debug-only UIFixture. Those tests now construct UpkeepStore directly; they calculate reservations with temporary or nonexistent fixture paths and never launch a scanner or mutation. Both tests passed in a focused release run after the responsiveness fixture passed. No full release-suite run is claimed.
