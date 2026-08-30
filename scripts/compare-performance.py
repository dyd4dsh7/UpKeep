#!/usr/bin/env python3
"""Compare the seven post-warm-up samples emitted by benchmark-performance.sh."""

import argparse
import statistics
from pathlib import Path


def read_samples(path):
    samples = {}
    for line in Path(path).read_text().splitlines():
        if not line.startswith("RESPONSIVENESS "):
            continue
        fields = dict(field.split("=", 1) for field in line.split()[1:])
        key = (int(fields["size"]), int(fields["sample"]))
        if key in samples:
            raise ValueError(f"Duplicate sample {key} in {path}")
        samples[key] = {name: float(value) for name, value in fields.items()}
    if set(samples) != {(size, sample) for size in (200, 2000) for sample in range(1, 8)}:
        raise ValueError(f"Expected seven samples at each fixture size in {path}")
    return samples


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("before")
    parser.add_argument("after", nargs="?")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--paired-search", action="store_true", help="Compare alternating reference/optimized search in one log")
    mode.add_argument("--search", action="store_true", help="Compare global search samples")
    mode.add_argument("--services", action="store_true", help="Compare diagnostics and release-menu samples")
    args = parser.parse_args()
    if args.paired_search:
        compare_search(args.before, args.before, paired=True)
        return
    if args.after is None:
        parser.error("after is required unless --paired-search is used")
    if args.search:
        compare_search(args.before, args.after)
        return
    if args.services:
        compare_services(args.before, args.after)
        return
    before, after = read_samples(args.before), read_samples(args.after)
    for key in before:
        if before[key]["checksum"] != after[key]["checksum"]:
            raise ValueError(f"Result checksum changed for {key}")

    print("| Items per collection | Operation | Before median (ms) | After median (ms) | Reduction |")
    print("| --- | --- | ---: | ---: | ---: |")
    for size in (200, 2000):
        for metric, label, divisor in (
            ("lookup_ms", "App/source/package lookup pass", 1),
            ("count20_ms", "One primary update-count read", 20),
            ("exclusion20_ms", "One exclusion pass over all app keys", 20),
            ("rebuild_ms", "Reassign app + Homebrew inventories", 1),
        ):
            old = statistics.median(row[metric] for key, row in before.items() if key[0] == size) / divisor
            new = statistics.median(row[metric] for key, row in after.items() if key[0] == size) / divisor
            print(f"| {size:,} | {label} | {old:.3f} | {new:.3f} | {(1 - new / old) * 100:.1f}% |")


def read_service_samples(path):
    samples = {}
    for line in Path(path).read_text().splitlines():
        if not line.startswith(("SERVICE_BENCHMARK ", "RELEASE_MENU_BENCHMARK ")):
            continue
        kind, *fields = line.split()
        row = {key: float(value) for key, value in (field.split("=", 1) for field in fields)}
        key = (kind, int(row.get("size", 2000)), int(row["sample"]))
        if key in samples:
            raise ValueError(f"Duplicate sample {key} in {path}")
        samples[key] = row
    expected = {(kind, size, sample) for kind, size in (
        ("SERVICE_BENCHMARK", 2000), ("RELEASE_MENU_BENCHMARK", 200), ("RELEASE_MENU_BENCHMARK", 5000)
    ) for sample in range(1, 8)}
    if set(samples) != expected:
        raise ValueError(f"Expected seven samples for each service workload in {path}")
    return samples


def compare_services(before_path, after_path):
    before, after = read_service_samples(before_path), read_service_samples(after_path)
    for key in before:
        for field in ("entries", "plain_strings", "mixed_strings", "results"):
            if before[key].get(field) != after[key].get(field):
                raise ValueError(f"Fixture or result count changed for {key}: {field}")
    print("| Operation | Before median (ms) | After median (ms) | Reduction |")
    print("| --- | ---: | ---: | ---: |")
    for kind, size, metric, label in (
        ("SERVICE_BENCHMARK", 2000, "diagnostics_load_ms", "Load 2,000 diagnostic entries"),
        ("SERVICE_BENCHMARK", 2000, "plain_redact_ms", "Redact 14,000 plain strings"),
        ("SERVICE_BENCHMARK", 2000, "mixed_redact_ms", "Redact 2,000 mixed strings"),
        ("RELEASE_MENU_BENCHMARK", 200, "elapsed_ms", "Prepare 200-release menu"),
        ("RELEASE_MENU_BENCHMARK", 5000, "elapsed_ms", "Prepare 5,000-release menu"),
    ):
        old = statistics.median(row[metric] for key, row in before.items() if key[:2] == (kind, size))
        new = statistics.median(row[metric] for key, row in after.items() if key[:2] == (kind, size))
        print(f"| {label} | {old:.3f} | {new:.3f} | {(1 - new / old) * 100:.1f}% |")



def read_search_samples(path, prefix="SEARCH_BENCHMARK "):
    samples = {}
    for line in Path(path).read_text().splitlines():
        if not line.startswith(prefix):
            continue
        fields = dict(field.split("=", 1) for field in line.split()[1:])
        key = (int(fields["size"]), fields["query"], int(fields["sample"]))
        if key in samples:
            raise ValueError(f"Duplicate sample {key} in {path}")
        samples[key] = (float(fields["elapsed_ms"]), int(fields["results"]))
    expected = {(size, query, sample) for size in (200, 2000)
                for query in ("name", "missing", "source", "dependency") for sample in range(1, 8)}
    if set(samples) != expected:
        raise ValueError(f"Expected seven samples for each search workload in {path}")
    return samples


def compare_search(before_path, after_path, paired=False):
    before = read_search_samples(before_path, "SEARCH_REFERENCE " if paired else "SEARCH_BENCHMARK ")
    after = read_search_samples(after_path)
    for key in before:
        if before[key][1] != after[key][1]:
            raise ValueError(f"Result count changed for {key}")
    print("| Items per main collection | Query | Before median (ms) | After median (ms) | Reduction |")
    print("| --- | --- | ---: | ---: | ---: |")
    for size in (200, 2000):
        for query in ("name", "missing", "source", "dependency"):
            old = statistics.median(row[0] for key, row in before.items() if key[:2] == (size, query))
            new = statistics.median(row[0] for key, row in after.items() if key[:2] == (size, query))
            print(f"| {size:,} | {query} | {old:.3f} | {new:.3f} | {(1 - new / old) * 100:.1f}% |")


if __name__ == "__main__":
    main()
