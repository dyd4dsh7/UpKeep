# Real command-process workload baseline

One warm-up and seven optimized samples enqueue 64 harmless shell commands across eight separately copied/ad-hoc-signed fixture executables. Copies/signatures and compilation are outside timing. CommandRunner starts its admitted commands; each publishes its actual shell PID and waits for a release file. The fixture waits for eight ready markers and holds for an additional requested 150 ms before reading PID receipts and checking kernel liveness. It then releases all commands and verifies every exit status is zero and all 64 markers exist.

| Measurement | Result |
| --- | ---: |
| Offered commands per sample | 64 |
| Admitted command leaders before release | 8 |
| Live command leaders at held snapshot | 8 |
| Maximum observed per executable at held snapshot | 2 |
| Completed commands per sample | 64 |
| Median completion including fixture hold (ms) | 1234.421 |
| Test-process RSS high-water across samples (MiB) | 21.906 |

Every sample satisfies these bounds, including the warm-up. The measurements establish the admission contract for a backlog eight times the global command limit. PID liveness is checked at the held snapshot, not continuously sampled throughout execution. Shell sleep helpers are additional descendants; eight counts admitted command leaders, not every process in their trees or all OS processes. Per-executable maxima can be one or two depending on scheduling; the asserted bound is two.

Completion timing includes task admission, process execution, pipe draining and the explicit hold; it is not a real scanner/network latency figure or a before/after speedup. macOS getrusage(RUSAGE_SELF) reports test-process high-water RSS, including runtime/allocator and earlier setup/samples. It excludes command-child memory and is not total tree memory. Only generated fixture shell copies were signed/executed; no package manager, network request or privileged mutation ran.

The separate destination admission fixture also passes on the current optimized binary: six offered shell commands across two destination keys admit exactly two per destination before release and complete all six afterward. The [1,000-check source benchmark](2026-10-01-concurrency.md) separately measures gate memory and simulated rate-limit outcomes. Neither fixture claims real publisher rates or app memory.

Raw measurements and source fingerprint: [2026-10-01-process-load.txt](2026-10-01-process-load.txt). Reproduce in isolation with `bash scripts/benchmark-performance.sh outputs/performance/processes.log processes`. CI's regular isolated global-admission test now offers 64 commands; the timing step additionally runs the warm-up and seven samples and retains its log. No hard timing/memory threshold or remote CI result is implied.
