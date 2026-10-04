#!/usr/bin/env python3
"""Promote a benchmark run summary to benchmarks/baseline/summary.json."""

from __future__ import annotations

import argparse
import copy
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.py import benchmark_common
from tool.py.benchmark_common import captured_at_now, ensure_on_path, flatten_suite_metrics, load_summary, write_json
from tool.benchmarks.compare_benchmark_summary import resolve_latest_results_summary
from tool.benchmarks.run_benchmark_suite import complete_suite_metrics


def promote_summary(source: Path, *, dry_run: bool = False) -> Path:
    summary = copy.deepcopy(load_summary(source))
    if summary.get("schema_version") != 2:
        raise ValueError("Only complete v2 measurements can be promoted; v1 remains readable history")
    if not summary.get('dependencies') or not all(summary.get('machine', {}).get(key) for key in ('dart_version', 'flutter_version', 'dependencies_sha256', 'host_fingerprint')):
        raise ValueError('Promotion requires SDK, dependency versions and host metadata')
    if summary.get("qualification") != "pass" or not benchmark_common.approved_controlled_comparison(summary.get('comparison', {})):
        raise ValueError("Promotion requires valid measurements and an approved controlled comparison")
    identity = {key: summary.get('git', {}).get(key) for key in ('commit_sha', 'source_sha256')}
    if not all(identity.values()) or summary['comparison'].get('candidate') != identity:
        raise ValueError('Controlled comparison must identify the same measured source')
    measured = [suite for suite in summary.get("suites", []) if suite.get("status") != "skipped"]
    if not measured or any(suite.get("status") != "pass" or not complete_suite_metrics(suite) or not suite.get("comparison_identity") or not suite.get("metric_metadata") for suite in measured):
        raise ValueError("Incomplete or failed benchmark suites cannot be promoted")
    if not flatten_suite_metrics(summary):
        raise ValueError('No performance metrics available for promotion')

    summary["run_id"] = "baseline"
    summary['$schema'] = '../schema/summary.schema.json'
    summary["captured_at"] = captured_at_now()
    # Retain the measured source revision, including its dirty flag.
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

import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]
_ROOT = _TOOL_DIR.parent
for _entry in (str(_ROOT), str(_TOOL_DIR)):
    if _entry not in sys.path:
        sys.path.insert(0, _entry)
