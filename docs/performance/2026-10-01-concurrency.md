# Offline source concurrency baseline

One warm-up and seven measured optimized samples compare the actual production SourceRequestGate.shared with an unbounded fixture reference. Each sample offers 1,000 checks across eight simulated hosts; every attempt holds a 64 KiB payload across a requested 2 ms sleep, including rejected attempts. A deliberate upstream fixture policy rejects attempts arriving while more than two checks are active for that host. This is a simulated concurrency rejection, not a real HTTP 429 or a publisher-derived threshold. No network traffic or child process is launched.

| Measurement | Production gate | Unbounded fixture |
| --- | ---: | ---: |
| Completion median (ms) | 522.756 | 4.725 |
| Maximum active checks | 8 | 1000 |
| Maximum per-host checks | 2 | 125 |
| Peak modeled payload budget (MiB) | 0.500 | 62.500 |
| Process peak RSS high-water (MiB) | 21.453 | 87.016 |
| Simulated 429s per sample | 0 | 984 |

Both policies complete all 1,000 attempted checks with checksum 249012 in every sample. The gated policy satisfies all 1,000 checks under the fixture rule; the unbounded policy has 16 accepted attempts and 984 simulated rejections. Its shorter duration does not establish a faster successful scan: this fixture has no retry policy. The gate deliberately trades offered concurrency for lower active payload demand and rejection risk. These measurements establish a fixture baseline, not live publisher rates, real scan duration or a production speedup.

The payload budget is calculated from peak active fixture operations times 64 KiB; it is not a direct measurement of live Data allocation or child-process memory. Peak RSS uses macOS getrusage(RUSAGE_SELF).ru_maxrss in bytes and includes Swift Testing, runtime, allocator retention and all earlier samples in that process. Policies run in separate filtered processes so neither inherits the other's high-water mark. RSS differences are evidence for this exact fixture, not a prediction for Upkeep's app or scanner memory. The 2 ms requested sleep is subject to scheduler/timer overhead.

Actual subprocess admission is covered separately by CommandRunner fixtures: two per executable/destination and eight global owned command processes. Those do not measure a 1,000-process workload. Existing foreground/aged-background, cancelled-waiter, queue-expiry and redirect-origin tests cover their own contracts; this timing fixture does not replace them. Large actual-process measurement remains open.

Raw samples and source fingerprint: [2026-10-01-concurrency.txt](2026-10-01-concurrency.txt). Reproduce each policy in its own process with benchmark-performance.sh modes concurrency and concurrency-unbounded. CI retains both logs and asserts gate/correctness bounds without hard timing or memory regression thresholds. No remote CI run is implied.
