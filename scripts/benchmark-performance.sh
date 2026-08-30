#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
LOG_PATH="${1:-outputs/performance/responsiveness.log}"
PAIRED_SEARCH=0
case "${2:-responsiveness}" in
  responsiveness)
    BENCHMARK_VARIABLE=UPKEEP_RESPONSIVENESS_BENCHMARK
    BENCHMARK_FILTER=responsivenessBenchmark
    ;;
  services)
    BENCHMARK_VARIABLE=UPKEEP_SERVICE_BENCHMARK
    BENCHMARK_FILTER=servicePerformanceBenchmark
    ;;
  search|search-paired)
    if [[ "${2}" == search-paired ]]; then PAIRED_SEARCH=1; fi
    BENCHMARK_VARIABLE=UPKEEP_SEARCH_BENCHMARK
    BENCHMARK_FILTER=searchPerformanceBenchmark
    ;;
  *)
    echo "usage: $0 [output-log] [responsiveness|services|search|search-paired]" >&2
    exit 2
    ;;
esac
mkdir -p "$(dirname "$LOG_PATH")"

# Compilation is outside the timed regions. The test performs one warm-up and
# seven samples at each size, checking results without invoking live scanners.
{
  date -u '+Measured at: %Y-%m-%dT%H:%M:%SZ'
  git rev-parse HEAD
  swift --version
  sw_vers
  env "${BENCHMARK_VARIABLE}=1" "UPKEEP_SEARCH_PAIRED=${PAIRED_SEARCH}" swift test -c release --filter "$BENCHMARK_FILTER"
} 2>&1 | tee "$LOG_PATH"
