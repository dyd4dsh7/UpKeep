# Current offline service and paired-search measurements

Measured from the current working tree on 1 October 2026 in release mode using the macOS 26.5 SDK and Swift warnings as errors. The two selected benchmark tests passed. Fixtures use isolated settings/files, no live scanners, network requests or package mutations. Measurements exclude compilation. This is not a new full release test-suite run or a rendered frame-time measurement.

Search alternates reference and optimized execution order, takes one warm-up plus seven samples per query/size, and asserts identical result identities and ordering. These within-run comparisons support the measured fixture-specific reduction; they do not establish all real-world search latency.

| Items per main collection | Query | Reference median | Optimized median | Reduction |
| --- | --- | ---: | ---: | ---: |
| 200 | Name | 3.351 ms | 2.876 ms | 14.2% |
| 200 | Missing | 4.046 ms | 3.041 ms | 24.8% |
| 200 | Source | 4.689 ms | 3.613 ms | 22.9% |
| 200 | Dependency | 4.709 ms | 3.713 ms | 21.2% |
| 2,000 | Name | 44.819 ms | 39.527 ms | 11.8% |
| 2,000 | Missing | 57.104 ms | 42.209 ms | 26.1% |
| 2,000 | Source | 48.710 ms | 38.512 ms | 20.9% |
| 2,000 | Dependency | 50.950 ms | 40.897 ms | 19.7% |

Current service medians: load 2,000 diagnostics 12.793 ms; redact 14,000 plain strings 3.816 ms; redact 2,000 mixed strings 1.929 ms; prepare 200 releases 0.156 ms; prepare 5,000 releases 13.864 ms. Compared with the dated August after-repeat snapshot, diagnostics/redaction medians are lower and menu preparation medians higher. The separate dated runs do not establish a causal performance change.

Raw samples: `2026-10-01-services.txt` and `2026-10-01-search-paired.txt`. Temporary compilation/test log: `/tmp/upkeep-service-search-current.log`. Current rendered scrolling/animation, full scan latency and automatic cross-run regression thresholds remain unverified.
