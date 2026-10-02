# Current responsiveness fixture measurements

Measured locally on 1 October 2026 from the current working tree in release mode, with Swift warnings treated as errors and the macOS 26.5 SDK. These are offline code-path measurements with isolated settings, not rendered frame times, live scan latency or production benchmarks. One warm-up and seven samples were taken at each size; assertions verify fixture results. Compilation is outside timed regions.

| Items per collection | Lookup pass median | Primary count read median | Inventory reassignment median |
| --- | ---: | ---: | ---: |
| 200 | 0.271 ms | 0.085 ms | 0.446 ms |
| 2,000 | 2.729 ms | 0.829 ms | 4.152 ms |

Raw samples: `2026-10-01-responsiveness.txt`. The full temporary build/test log is `/tmp/upkeep-responsiveness-current.log`. The focused release benchmark passed. This does not constitute a new full release test-suite run.

The comparison script validated matching checksums against `after-repeat.txt`, the dated August snapshot. Current median lookup/count reads are lower; 200-item inventory reassignment is higher by about 10.5%, while the 2,000-item reassignment is lower by about 4.9%. This is a comparison across dated runs, without a fresh controlled before build, so the differences cannot be attributed to the current implementation alone. No hard performance gate is justified by these observations.

CI now uses fixture dependencies for its launch smoke test and retains offline responsiveness, service and paired-search logs for 30 days. Paired search produces a within-run comparison summary. Remote CI execution, automatic cross-run regression evaluation, rendered smoke assertions and oldest-supported-runtime coverage remain unverified.
