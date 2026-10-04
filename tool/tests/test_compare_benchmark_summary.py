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
    metric_metadata,
)


class CompareBenchmarkSummaryTests(unittest.TestCase):
    def test_limits_cannot_be_weakened_by_generic_threshold(self) -> None:
        for metric, current in [('p95_us', 106), ('queries_per_second', 84), ('heap_growth_bytes', 111)]:
            self.assertTrue(compare_metrics({metric: 100}, {metric: current}, threshold=0.25)[0].regression)

    def test_measured_zero_baseline_is_compared(self) -> None:
        self.assertFalse(compare_metrics({'heap_growth_bytes': 0}, {'heap_growth_bytes': 0}, threshold=0.1)[0].regression)
        self.assertTrue(compare_metrics({'heap_growth_bytes': 0}, {'heap_growth_bytes': 1}, threshold=0.1)[0].regression)

    def test_units_and_query_throughput_direction(self) -> None:
        self.assertFalse(metric_lower_is_better('workerCount=4.queries_per_second'))
        self.assertEqual(metric_metadata('streamQueryBatched.fetch_size')['unit'], 'rows')
        self.assertEqual(metric_metadata('streamQueryBatched.chunk_size')['unit'], 'bytes')
        self.assertEqual(metric_metadata('queries_per_second')['unit'], 'queries/s')
    def test_workload_and_process_startup_are_not_performance_metrics(self) -> None:
        summary = {'suites': [{'id': 'test', 'status': 'pass', 'metrics': {
            'rows': 8000, 'chunk_size': 1048576, 'wall_ms': 999, 'input_payload_bytes': 10,
            'p95_us': 100, 'timeouts': 0}}]}
        self.assertEqual(flatten_suite_metrics(summary), {'test.p95_us': 100})

    def test_failed_suite_cannot_supply_comparison_metrics(self) -> None:
        self.assertEqual(flatten_suite_metrics({'suites': [{'id': 'test', 'status': 'fail', 'metrics': {'p95_us': 100}}]}), {})

    def test_no_comparable_metrics_returns_inconclusive(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'summary.json'
            path.write_text(json.dumps({'schema_version': 2, 'suites': []}))
            self.assertEqual(main(['--baseline', str(path), '--current', str(path)]), 2)

    def test_metric_direction_heuristics(self) -> None:
        self.assertTrue(metric_lower_is_better("transport_pipeline.latency_ms"))
        self.assertTrue(metric_lower_is_better("odbc_async.p95_ms"))
        self.assertTrue(metric_lower_is_better("odbc_gateway_encoding.median_us_highThroughput_columnar"))
        self.assertFalse(metric_lower_is_better("odbc_async.rows_per_sec"))
        self.assertFalse(metric_lower_is_better("plug_agente_stack.config_cache.speedup"))

    def test_compare_metrics_detects_timing_regression(self) -> None:
        diffs = compare_metrics(
            {"transport_pipeline.latency_ms": 100.0},
            {"transport_pipeline.latency_ms": 130.0},
            threshold=0.20,
        )
        self.assertEqual(len(diffs), 1)
        self.assertTrue(diffs[0].regression)
        self.assertIn("YES", format_table(diffs))

    def test_compare_metrics_allows_small_timing_change(self) -> None:
        diffs = compare_metrics(
            {"transport_pipeline.latency_ms": 100.0},
            {"transport_pipeline.latency_ms": 115.0},
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
                    "metrics": {"latency_ms": 10.0, "enabled": True},
                }
            ]
        }
        flattened = flatten_suite_metrics(summary)
        self.assertEqual(flattened, {"transport_pipeline.latency_ms": 10.0})

    def test_odbc_metrics_are_excluded_when_comparison_identity_is_missing(self) -> None:
        baseline = {
            "suites": [
                {"id": "odbc_streaming", "metrics": {"latency_ms": 42.0}},
                {"id": "transport_pipeline", "comparison_identity": {"benchmark_profile": "test_v1"}, "metrics": {"latency_ms": 100.0}},
            ]
        }
        current = {
            "suites": [
                {
                    "id": "odbc_streaming",
                    "comparison_identity": {"package_version": "4.5.1"},
                    "metrics": {"latency_ms": 183.0},
                },
                {"id": "transport_pipeline", "comparison_identity": {"benchmark_profile": "test_v1"}, "metrics": {"latency_ms": 100.0}},
            ]
        }

        excluded = incompatible_benchmark_suite_reasons(baseline, current)

        self.assertEqual(excluded, {"odbc_streaming": "missing comparison identity"})
        self.assertEqual(
            flatten_suite_metrics(current, excluded_suite_ids=excluded),
            {"transport_pipeline.latency_ms": 100.0},
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

    def test_cli_unqualified_regression_data_is_inconclusive(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            baseline = {
                "suites": [
                    {"id": "transport_pipeline", "comparison_identity": {"benchmark_profile": "test_v1"}, "metrics": {"latency_ms": 100.0}},
                ]
            }
            current = {
                "suites": [
                    {"id": "transport_pipeline", "comparison_identity": {"benchmark_profile": "test_v1"}, "metrics": {"latency_ms": 200.0}},
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
            self.assertEqual(exit_code, 2)

    def test_cli_unqualified_data_cannot_approve(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            baseline = {
                "suites": [
                    {"id": "transport_pipeline", "comparison_identity": {"benchmark_profile": "test_v1"}, "metrics": {"latency_ms": 100.0}},
                ]
            }
            current = {
                "suites": [
                    {"id": "transport_pipeline", "comparison_identity": {"benchmark_profile": "test_v1"}, "metrics": {"latency_ms": 105.0}},
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
            self.assertEqual(exit_code, 2)


if __name__ == "__main__":
    unittest.main()
