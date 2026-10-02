# Cached primary badge-count evidence

The current optimized build caches the primary update count using app/Homebrew/macOS result generation, exclusion revision and earliest exclusion expiry. Developer/model progress and unrelated diagnostics are outside the inventory cache key. Skipped targets becoming a new available version invalidate through update inventory changes; settings edits invalidate through the revision. A past expiry always prevents cache reuse even if the expiry task has not run yet.

The same responsiveness fixture ran before and after caching, with one warm-up and seven samples at each size. Compilation is outside timing. Fixture checksums remain 6500 and 65000. Each measured batch contains 20 count reads; inventory reassignment invalidates the cache before the next batch, so the cached result includes one cold read and 19 warm reads. These are batch timings, not isolated warm-read latency.

| Items per collection | Before median, 20 reads (ms) | Cached median, 20 reads (ms) | Reduction |
| --- | ---: | ---: | ---: |
| 200 | 1.690541 | 0.084875 | 95.0% |
| 2,000 | 17.535042 | 0.778583 | 95.6% |

Raw samples, the prior app binary fingerprint and current source-tree fingerprint are in 2026-10-01-count-cache.txt. Measurements are separate runs on the same host, not randomized paired builds; timing noise is uncontrolled. The results establish lower repeated-count fixture work, not native frame time, view-body count, network performance or application memory. Native menu/badge rendering remains unverified.
