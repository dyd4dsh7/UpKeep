# Offline progressive publication baseline

One warm-up and seven measured optimized samples exercise the actual UpkeepStore progress callback using an injected scanner. Each sample publishes discovery and one usable application update, waits for the store to expose that update while scanning, holds final completion for a simulated 50 ms optional-source tail, then returns the same result. No live discovery, network request or package-manager command runs. Compilation is outside timed regions.

| Measurement | Median (ms) |
| --- | ---: |
| Store-recorded first source result | 0.110 |
| Test-observed usable update | 2.219 |
| Final store completion | 61.489 |

The observer polls the actor-backed fixture, so its timing includes polling/scheduling overhead. The recorded first-result metric uses Date; observation and total duration use ContinuousClock. The 50 ms tail is deliberately simulated and subject to scheduling. These figures establish an offline publication baseline, not real scan duration or a production speedup. A return-only caller would receive this fixture's result at final completion; that reference is not a separately measured old build.

Every sample asserts the update is usable before completion, persists afterward and does not reset the first-result metric. Existing source/store regressions separately cover per-manager/runtime publication, failed scopes, and newer targeted or installed results surviving an older scan. Source audit confirms app checks begin after discovery without waiting for Homebrew, macOS, developer or model completion. Native UI rendering is not measured.

Raw samples and source fingerprint: [2026-10-01-progress-publication.txt](2026-10-01-progress-publication.txt). Reproduce with `bash scripts/benchmark-performance.sh outputs/performance/progress.log progress`; CI retains the log alongside the other offline benchmarks. No timing threshold is asserted.
