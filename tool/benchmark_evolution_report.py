#!/usr/bin/env python3
"""List benchmark runs and show metric deltas versus the committed baseline."""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tool.compare_benchmark_summary import compare_metrics, format_table
from tool.py.benchmark_common import (
    BASELINE_PATH,
    HISTORY_DIR,
    RESULTS_DIR,
    ensure_on_path,
    flatten_suite_metrics,
    load_summary,
)


@dataclass(frozen=True)
class RunReport:
    run_id: str
    source: Path
    captured_at: str
    suite_count: int
    metric_count: int
    regression_count: int
    diffs: list


def discover_summaries(root: Path) -> list[Path]:
    if not root.is_dir():
        return []
    summaries = [path / "summary.json" for path in root.iterdir() if path.is_dir()]
    return sorted(
        (path for path in summaries if path.is_file()),
        key=lambda path: path.parent.name,
        reverse=True,
    )


def build_run_report(summary_path: Path, baseline_metrics: dict[str, float], threshold: float) -> RunReport:
    summary = load_summary(summary_path)
    current_metrics = flatten_suite_metrics(summary)
    diffs = compare_metrics(baseline_metrics, current_metrics, threshold=threshold)
    regressions = [diff for diff in diffs if diff.regression]
    return RunReport(
        run_id=str(summary.get("run_id", summary_path.parent.name)),
        source=summary_path,
        captured_at=str(summary.get("captured_at", "")),
        suite_count=len(summary.get("suites", [])),
        metric_count=len(diffs),
        regression_count=len(regressions),
        diffs=diffs,
    )


def format_run_header(report: RunReport) -> str:
    status = "REGRESSION" if report.regression_count else "ok"
    return (
        f"{report.run_id}  captured={report.captured_at or 'n/a'}  "
        f"suites={report.suite_count}  metrics={report.metric_count}  "
        f"regressions={report.regression_count}  [{status}]"
    )


def main(argv: list[str] | None = None) -> int:
    ensure_on_path()
    parser = argparse.ArgumentParser(description="Benchmark evolution report vs baseline.")
    parser.add_argument("--baseline", type=Path, default=BASELINE_PATH, help="Baseline summary.json")
    parser.add_argument(
        "--results-dir",
        type=Path,
        default=RESULTS_DIR,
        help="Ephemeral results root (default: benchmarks/results/)",
    )
    parser.add_argument(
        "--history-dir",
        type=Path,
        default=HISTORY_DIR,
        help="Committed history root (default: benchmarks/history/)",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.20,
        help="Regression threshold as fraction (default: 0.20 = 20%%)",
    )
    parser.add_argument(
        "--include-history",
        action="store_true",
        help="Include committed benchmarks/history/ runs.",
    )
    parser.add_argument(
        "--details",
        action="store_true",
        help="Print per-metric tables for each run.",
    )
    args = parser.parse_args(argv)

    if not args.baseline.is_file():
        print(f"Baseline not found: {args.baseline}")
        return 2

    baseline_summary = load_summary(args.baseline)
    baseline_metrics = flatten_suite_metrics(baseline_summary)
    if not baseline_metrics:
        print(f"Baseline has no numeric suite metrics: {args.baseline}")
        print("Promote a known-good run with: python tool/promote_benchmark_baseline.py --from <summary.json>")

    summaries = discover_summaries(args.results_dir)
    if args.include_history:
        summaries.extend(discover_summaries(args.history_dir))
        summaries = sorted(set(summaries), key=lambda path: path.parent.name, reverse=True)

    print(f"Baseline: {args.baseline}")
    print(f"Threshold: {args.threshold * 100:.0f}%")
    print()

    if not summaries:
        print("No benchmark runs found.")
        return 0

    total_regressions = 0
    for summary_path in summaries:
        report = build_run_report(summary_path, baseline_metrics, args.threshold)
        total_regressions += report.regression_count
        print(format_run_header(report))
        if args.details and report.diffs:
            print(format_table(report.diffs))
            print()

    print()
    if total_regressions:
        print(f"{total_regressions} regression(s) detected across {len(summaries)} run(s).")
        return 1

    print(f"No regressions above threshold across {len(summaries)} run(s).")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
