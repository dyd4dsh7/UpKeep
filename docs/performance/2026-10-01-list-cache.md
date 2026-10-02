# Paired offline list projection evidence

The optimized developer-list fixture compares the current cached getter with the prior two-stage uncached manager/current/query filtering policy. Each timed batch performs 20 reads. Inventory reassignment invalidates the cache outside timing before every sample, so the cached batch includes one cold read and 19 warm reads. Execution order alternates, with one warm-up and seven samples at 200 and 2,000 packages. All checksums and resulting IDs match; fixtures never invoke a scanner, command or network service.

| Packages | Uncached median batch (ms) | Cached median batch (ms) | Reduction |
| --- | ---: | ---: | ---: |
| 200 | 3.715084 | 0.192792 | 94.8% |
| 2,000 | 38.654584 | 1.866625 | 95.2% |

Raw samples and source fingerprint are in 2026-10-01-list-cache.txt. The reference uses loaded fixture values and the same filter policy; it does not reconstruct an old application binary or its rendered view behavior. These results cover repeated developer filtering, not every list's timings, view-specific sorting, frames or memory. Native validation remains open. scripts/benchmark-performance.sh supports the lists mode, and CI retains its raw log; no remote run is claimed.
