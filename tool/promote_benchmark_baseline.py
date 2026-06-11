#!/usr/bin/env python3
"""Promote a benchmark run summary to benchmarks/baseline/summary.json."""

from __future__ import annotations

import argparse
import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tool.py import benchmark_common
from tool.py.benchmark_common import captured_at_now, ensure_on_path, load_summary, write_json
from tool.compare_benchmark_summary import resolve_latest_results_summary


def promote_summary(source: Path, *, dry_run: bool = False) -> Path:
    summary = copy.deepcopy(load_summary(source))
    if summary.get("schema_version") != 1:
        raise ValueError(f"Unsupported schema_version in {source}")

    summary["run_id"] = "baseline"
    summary["captured_at"] = captured_at_now()
    summary["git"] = {
        "commit_sha": "baseline",
        "branch": "baseline",
        "dirty": False,
    }
    notes = list(summary.get("notes") or [])
    notes.append(f"Promoted from {source.as_posix()}")
    summary["notes"] = notes

    baseline_path = benchmark_common.BASELINE_PATH
    if dry_run:
        print(f"Would promote {source} -> {baseline_path}")
        print(f"  suites: {len(summary.get('suites', []))}")
        return baseline_path

    write_json(baseline_path, summary)
    print(f"Promoted baseline: {baseline_path}")
    return baseline_path


def main(argv: list[str] | None = None) -> int:
    ensure_on_path()
    parser = argparse.ArgumentParser(description="Promote a benchmark summary to the committed baseline.")
    parser.add_argument(
        "--from",
        dest="source",
        type=Path,
        help="Source summary.json (default: latest under benchmarks/results/)",
    )
    parser.add_argument("--dry-run", action="store_true", help="Show what would be promoted.")
    args = parser.parse_args(argv)

    source = args.source
    if source is None:
        latest = resolve_latest_results_summary(benchmark_common.RESULTS_DIR)
        if latest is None:
            print("No --from path and no benchmarks/results/<run_id>/summary.json found.")
            return 2
        source = latest

    if not source.is_file():
        print(f"Source summary not found: {source}")
        return 2

    try:
        promote_summary(source, dry_run=args.dry_run)
    except ValueError as error:
        print(str(error))
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
