#!/usr/bin/env python3
"""
Compare two benchmark summary.json files and flag regressions.

Lower is better for timing metrics (*_ms, *_us, p50/p95/p99, wall_ms).
Higher is better for throughput metrics (rows_per_sec, ops_per_sec, throughput).
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tool.py.benchmark_common import (
    ensure_on_path,
    flatten_suite_metrics,
    load_summary,
    metric_lower_is_better,
)


@dataclass(frozen=True)
class MetricDiff:
    metric: str
    baseline: float
    current: float
    delta_pct: float
    direction: str
    regression: bool


def compare_metrics(
    baseline_metrics: dict[str, float],
    current_metrics: dict[str, float],
    *,
    threshold: float,
) -> list[MetricDiff]:
    diffs: list[MetricDiff] = []
    for key in sorted(set(baseline_metrics) & set(current_metrics)):
        baseline_value = baseline_metrics[key]
        current_value = current_metrics[key]
        if baseline_value == 0:
            continue
        delta_pct = ((current_value - baseline_value) / baseline_value) * 100.0
        lower_is_better = metric_lower_is_better(key)
        if lower_is_better:
            regression = current_value > baseline_value * (1.0 + threshold)
            direction = "lower is better"
        else:
            regression = current_value < baseline_value * (1.0 - threshold)
            direction = "higher is better"
        diffs.append(
            MetricDiff(
                metric=key,
                baseline=baseline_value,
                current=current_value,
                delta_pct=delta_pct,
                direction=direction,
                regression=regression,
            )
        )
    return diffs


def format_table(diffs: list[MetricDiff]) -> str:
    if not diffs:
        return "No overlapping numeric metrics to compare."

    headers = ("metric", "baseline", "current", "delta %", "direction", "regression")
    rows = [
        (
            diff.metric,
            f"{diff.baseline:.4g}",
            f"{diff.current:.4g}",
            f"{diff.delta_pct:+.2f}%",
            diff.direction,
            "YES" if diff.regression else "no",
        )
        for diff in diffs
    ]
    widths = [len(header) for header in headers]
    for row in rows:
        for index, cell in enumerate(row):
            widths[index] = max(widths[index], len(cell))

    def _line(cells: tuple[str, ...]) -> str:
        return "  ".join(cell.ljust(widths[index]) for index, cell in enumerate(cells))

    lines = [_line(headers), _line(tuple("-" * width for width in widths))]
    lines.extend(_line(row) for row in rows)
    return "\n".join(lines)


def resolve_latest_results_summary(results_dir: Path) -> Path | None:
    if not results_dir.is_dir():
        return None
    candidates = sorted(
        (path / "summary.json" for path in results_dir.iterdir() if path.is_dir()),
        key=lambda path: path.parent.name,
        reverse=True,
    )
    for candidate in candidates:
        if candidate.is_file():
            return candidate
    return None


def main(argv: list[str] | None = None) -> int:
    ensure_on_path()
    parser = argparse.ArgumentParser(description="Compare benchmark summary files.")
    parser.add_argument("--baseline", required=True, type=Path, help="Baseline summary.json path")
    parser.add_argument(
        "--current",
        type=Path,
        help="Current summary.json path (default: latest under benchmarks/results/)",
    )
    parser.add_argument(
        "--threshold",
        type=float,
        default=0.20,
        help="Regression threshold as fraction (default: 0.20 = 20%%)",
    )
    args = parser.parse_args(argv)

    if args.current is None:
        from tool.py.benchmark_common import RESULTS_DIR

        latest = resolve_latest_results_summary(RESULTS_DIR)
        if latest is None:
            print("No current summary provided and no benchmarks/results/<run_id>/summary.json found.")
            return 2
        current_path = latest
    else:
        current_path = args.current

    baseline_summary = load_summary(args.baseline)
    current_summary = load_summary(current_path)
    baseline_metrics = flatten_suite_metrics(baseline_summary)
    current_metrics = flatten_suite_metrics(current_summary)

    print(f"Baseline: {args.baseline}")
    print(f"Current:  {current_path}")
    print(f"Threshold: {args.threshold * 100:.0f}%")
    print()

    diffs = compare_metrics(baseline_metrics, current_metrics, threshold=args.threshold)
    print(format_table(diffs))

    regressions = [diff for diff in diffs if diff.regression]
    if regressions:
        print()
        print(f"Regression detected in {len(regressions)} metric(s).")
        return 1

    if not diffs:
        print()
        print("No overlapping metrics; comparison is inconclusive.")
    else:
        print()
        print("No regressions above threshold.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
