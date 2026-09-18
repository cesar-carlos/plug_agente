from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.benchmarks.compare_benchmark_summary import compare_metrics, format_table, main
from tool.py.benchmark_common import (
    flatten_suite_metrics,
    incompatible_benchmark_suite_reasons,
    metric_lower_is_better,
)


class CompareBenchmarkSummaryTests(unittest.TestCase):
    def test_metric_direction_heuristics(self) -> None:
        self.assertTrue(metric_lower_is_better("transport_pipeline.wall_ms"))
        self.assertTrue(metric_lower_is_better("odbc_async.p95_ms"))
        self.assertTrue(metric_lower_is_better("odbc_gateway_encoding.median_us_highThroughput_columnar"))
        self.assertFalse(metric_lower_is_better("odbc_async.rows_per_sec"))
        self.assertFalse(metric_lower_is_better("plug_agente_stack.config_cache.speedup"))

    def test_compare_metrics_detects_timing_regression(self) -> None:
        diffs = compare_metrics(
            {"transport_pipeline.wall_ms": 100.0},
            {"transport_pipeline.wall_ms": 130.0},
            threshold=0.20,
        )
        self.assertEqual(len(diffs), 1)
        self.assertTrue(diffs[0].regression)
        self.assertIn("YES", format_table(diffs))

    def test_compare_metrics_allows_small_timing_change(self) -> None:
        diffs = compare_metrics(
            {"transport_pipeline.wall_ms": 100.0},
            {"transport_pipeline.wall_ms": 115.0},
            threshold=0.20,
        )
        self.assertEqual(len(diffs), 1)
        self.assertFalse(diffs[0].regression)

    def test_compare_metrics_detects_throughput_regression(self) -> None:
        diffs = compare_metrics(
            {"odbc_async.rows_per_sec": 1000.0},
            {"odbc_async.rows_per_sec": 700.0},
            threshold=0.20,
        )
        self.assertEqual(len(diffs), 1)
        self.assertTrue(diffs[0].regression)

    def test_flatten_suite_metrics(self) -> None:
        summary = {
            "suites": [
                {
                    "id": "transport_pipeline",
                    "metrics": {"wall_ms": 10.0, "enabled": True},
                }
            ]
        }
        flattened = flatten_suite_metrics(summary)
        self.assertEqual(flattened, {"transport_pipeline.wall_ms": 10.0})

    def test_odbc_metrics_are_excluded_when_comparison_identity_is_missing(self) -> None:
        baseline = {
            "suites": [
                {"id": "odbc_streaming", "metrics": {"wall_ms": 42.0}},
                {"id": "transport_pipeline", "metrics": {"wall_ms": 100.0}},
            ]
        }
        current = {
            "suites": [
                {
                    "id": "odbc_streaming",
                    "comparison_identity": {"package_version": "4.5.1"},
                    "metrics": {"wall_ms": 183.0},
                },
                {"id": "transport_pipeline", "metrics": {"wall_ms": 100.0}},
            ]
        }

        excluded = incompatible_benchmark_suite_reasons(baseline, current)

        self.assertEqual(excluded, {"odbc_streaming": "missing comparison identity"})
        self.assertEqual(
            flatten_suite_metrics(current, excluded_suite_ids=excluded),
            {"transport_pipeline.wall_ms": 100.0},
        )

    def test_odbc_metrics_are_excluded_when_workload_identity_differs(self) -> None:
        baseline = {
            "suites": [
                {
                    "id": "odbc_streaming",
                    "comparison_identity": {"package_version": "4.5.1", "rows": "100"},
                }
            ]
        }
        current = {
            "suites": [
                {
                    "id": "odbc_streaming",
                    "comparison_identity": {"package_version": "4.5.1", "rows": "200"},
                }
            ]
        }

        self.assertEqual(
            incompatible_benchmark_suite_reasons(baseline, current),
            {"odbc_streaming": "comparison identity differs"},
        )

    def test_cli_exit_code_on_regression(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            baseline = {
                "suites": [
                    {"id": "transport_pipeline", "metrics": {"wall_ms": 100.0}},
                ]
            }
            current = {
                "suites": [
                    {"id": "transport_pipeline", "metrics": {"wall_ms": 200.0}},
                ]
            }
            baseline_path = root / "baseline.json"
            current_path = root / "current.json"
            baseline_path.write_text(json.dumps(baseline), encoding="utf-8")
            current_path.write_text(json.dumps(current), encoding="utf-8")

            exit_code = main(
                [
                    "--baseline",
                    str(baseline_path),
                    "--current",
                    str(current_path),
                    "--threshold",
                    "0.20",
                ]
            )
            self.assertEqual(exit_code, 1)

    def test_cli_exit_code_without_regression(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            baseline = {
                "suites": [
                    {"id": "transport_pipeline", "metrics": {"wall_ms": 100.0}},
                ]
            }
            current = {
                "suites": [
                    {"id": "transport_pipeline", "metrics": {"wall_ms": 105.0}},
                ]
            }
            baseline_path = root / "baseline.json"
            current_path = root / "current.json"
            baseline_path.write_text(json.dumps(baseline), encoding="utf-8")
            current_path.write_text(json.dumps(current), encoding="utf-8")

            exit_code = main(
                [
                    "--baseline",
                    str(baseline_path),
                    "--current",
                    str(current_path),
                ]
            )
            self.assertEqual(exit_code, 0)


if __name__ == "__main__":
    unittest.main()
