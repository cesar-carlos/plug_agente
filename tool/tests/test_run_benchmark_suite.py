from __future__ import annotations

import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.py.benchmark_common import parse_transport_markdown_metrics
from tool.run_benchmark_suite import build_suite_plans, filter_suite_plans, main


class RunBenchmarkSuiteTests(unittest.TestCase):
    def test_dry_run_lists_transport_suite(self) -> None:
        with patch.dict("os.environ", {}, clear=True):
            exit_code = main(["--dry-run"])
        self.assertEqual(exit_code, 0)
        plans = build_suite_plans()
        ids = [plan["id"] for plan in plans]
        self.assertIn("transport_pipeline", ids)
        self.assertIn("odbc_async", ids)

    def test_filter_suite_plans_only_and_skip_dart_tool(self) -> None:
        plans = build_suite_plans()
        filtered = filter_suite_plans(plans, only={"transport_pipeline"}, skip_dart_tool=True)
        ids = [plan["id"] for plan in filtered]
        self.assertEqual(ids, ["transport_pipeline"])

    def test_parse_transport_markdown_metrics(self) -> None:
        sample = """
| case | path | mode | signed | cmp | original | wire | saved | send p50/p95/p99 | receive p50/p95/p99 | isolates |
| --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| small_sql_repetitive | async | auto | true | gzip | 1.0KB | 512B | 512B | 1.20ms / 1.50ms / 2.00ms | 0.80ms / 1.00ms / 1.20ms | 2 |
"""
        metrics = parse_transport_markdown_metrics(sample)
        key = "small_sql_repetitive.async.auto.signed_True.send_p50_us"
        self.assertIn(key, metrics)
        self.assertAlmostEqual(metrics[key], 1200.0)


if __name__ == "__main__":
    unittest.main()
