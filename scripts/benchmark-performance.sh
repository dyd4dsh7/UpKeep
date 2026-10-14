#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
LOG_PATH="${1:-outputs/performance/responsiveness.log}"
PAIRED_SEARCH=0
BENCHMARK_VALUE=1
PROCESS_STRESS=0
case "${2:-responsiveness}" in
  responsiveness)
    BENCHMARK_VARIABLE=UPKEEP_RESPONSIVENESS_BENCHMARK
    BENCHMARK_FILTER=responsivenessBenchmark
    ;;
  lists)
    BENCHMARK_VARIABLE=UPKEEP_LIST_BENCHMARK
    BENCHMARK_FILTER=listProjectionBenchmark
    ;;
  services)
    BENCHMARK_VARIABLE=UPKEEP_SERVICE_BENCHMARK
    BENCHMARK_FILTER=servicePerformanceBenchmark
    ;;
  progress)
    BENCHMARK_VARIABLE=UPKEEP_PROGRESS_BENCHMARK
    BENCHMARK_FILTER=progressivePublicationBenchmark
    ;;
  concurrency|concurrency-unbounded)
    BENCHMARK_VARIABLE=UPKEEP_CONCURRENCY_BENCHMARK
    BENCHMARK_FILTER=concurrencyPerformanceBenchmark
    BENCHMARK_VALUE=bounded
    if [[ "${2}" == concurrency-unbounded ]]; then BENCHMARK_VALUE=unbounded; fi
    ;;
  processes)
    BENCHMARK_VARIABLE=UPKEEP_PROCESS_BENCHMARK
    BENCHMARK_FILTER=globalProcessAdmissionAcrossDistinctExecutables
    PROCESS_STRESS=1
    ;;
  search|search-paired)
    if [[ "${2}" == search-paired ]]; then PAIRED_SEARCH=1; fi
    BENCHMARK_VARIABLE=UPKEEP_SEARCH_BENCHMARK
    BENCHMARK_FILTER=searchPerformanceBenchmark
    ;;
  *)
    echo "usage: $0 [output-log] [responsiveness|lists|services|progress|concurrency|concurrency-unbounded|processes|search|search-paired]" >&2
    exit 2
    ;;
esac
mkdir -p "$(dirname "$LOG_PATH")"

# Compilation is outside the timed regions. The test performs one warm-up and
# seven samples, checking results without invoking live scanners. Progress uses
# one fixture size and an explicit simulated slow-source tail.
{
  date -u '+Measured at: %Y-%m-%dT%H:%M:%SZ'
  git rev-parse HEAD
  swift --version
  sw_vers
  env "${BENCHMARK_VARIABLE}=${BENCHMARK_VALUE}" "UPKEEP_SEARCH_PAIRED=${PAIRED_SEARCH}" "UPKEEP_PROCESS_STRESS=${PROCESS_STRESS}" swift test -c release --filter "$BENCHMARK_FILTER"
} 2>&1 | tee "$LOG_PATH"
