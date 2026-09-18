from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.py.benchmark_common import (
    is_dart_ffi_compile_failure,
    parse_odbc_streaming_benchmark_metrics,
    parse_plug_agente_stack_metrics,
    parse_transport_markdown_metrics,
    resolve_dart_odbc_fast_root,
)
from tool.benchmarks.run_benchmark_suite import (
    DART_TOOL_SKIP_REASON,
    build_suite_plans,
    filter_suite_plans,
    main,
    run_transport_json_tool,
)


class RunBenchmarkSuiteTests(unittest.TestCase):
    def test_dry_run_lists_transport_suite(self) -> None:
        with patch.dict("os.environ", {}, clear=True):
            exit_code = main(["--dry-run"])
        self.assertEqual(exit_code, 0)
        plans = build_suite_plans()
        ids = [plan["id"] for plan in plans]
        self.assertIn("transport_pipeline", ids)
        self.assertIn("plug_agente_stack", ids)
        self.assertIn("odbc_async", ids)

    def test_filter_suite_plans_only_and_skip_dart_tool(self) -> None:
        plans = build_suite_plans()
        filtered = filter_suite_plans(plans, only={"transport_pipeline"}, skip_dart_tool=True)
        ids = [plan["id"] for plan in filtered]
        self.assertEqual(ids, ["transport_pipeline"])

    def test_skip_dart_tool_default_marks_transport_json_disabled(self) -> None:
        plans = build_suite_plans()
        filtered = filter_suite_plans(plans, only=None, skip_dart_tool=True)
        transport_json = next(plan for plan in filtered if plan["id"] == "transport_pipeline_json")
        self.assertFalse(transport_json.get("enabled"))
        self.assertIn("dart run", transport_json.get("skip_reason", ""))

    def test_skip_dart_tool_allows_explicit_only_transport_json(self) -> None:
        plans = build_suite_plans()
        filtered = filter_suite_plans(
            plans,
            only={"transport_pipeline_json"},
            skip_dart_tool=True,
        )
        self.assertEqual([plan["id"] for plan in filtered], ["transport_pipeline_json"])
        self.assertTrue(filtered[0].get("enabled"))

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

    def test_parse_transport_markdown_metrics_shell_prefix(self) -> None:
        sample = """
Shell: | case | path | mode | signed | cmp | original | wire | saved | send p50/p95/p99 | receive p50/p95/p99 | isolates |
Shell: | --- | --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
Shell: | small_sql_repetitive | async | auto | true | gzip | 1.0KB | 512B | 512B | 132us/208us/208us | 36us/71us/71us | 0 |
"""
        metrics = parse_transport_markdown_metrics(sample)
        key = "small_sql_repetitive.async.auto.signed_True.send_p50_us"
        self.assertIn(key, metrics)
        self.assertAlmostEqual(metrics[key], 132.0)

    def test_is_dart_ffi_compile_failure(self) -> None:
        self.assertTrue(is_dart_ffi_compile_failure(252, ""))
        self.assertTrue(
            is_dart_ffi_compile_failure(1, "Error: InvalidType in _FfiUseSiteTransformer")
        )
        self.assertFalse(is_dart_ffi_compile_failure(1, "generic failure"))

    def test_run_transport_json_tool_reclassifies_ffi_compile_failure(self) -> None:
        import tempfile
        from pathlib import Path

        with tempfile.TemporaryDirectory() as temp_dir:
            log_path = Path(temp_dir) / "transport_pipeline_json.log"
            log_path.write_text(
                "InvalidType: Not a valid type for FFI\n_FfiUseSiteTransformer failed\n",
                encoding="utf-8",
            )
            with patch(
                "tool.benchmarks.run_benchmark_suite.run_streaming",
                return_value=252,
            ):
                suite = run_transport_json_tool(log_path)
        self.assertEqual(suite["status"], "skipped")
        self.assertEqual(suite["reason"], DART_TOOL_SKIP_REASON)

    def test_parse_plug_agente_stack_metrics(self) -> None:
        sample = """
| scenario | variant | iterations | median_us | p95_us | speedup | rows_per_sec | notes |
| --- | --- | ---: | ---: | ---: | ---: | ---: | --- |
| columnar_stream_emitter | wire_only | 8 | 1200 | 1500 | 4.5 | 4166666.67 | rows=5000 |
"""
        metrics = parse_plug_agente_stack_metrics(sample)
        self.assertIn("columnar_stream_emitter.wire_only.median_us", metrics)
        self.assertEqual(metrics["columnar_stream_emitter.wire_only.median_us"], 1200.0)
        self.assertAlmostEqual(metrics["columnar_stream_emitter.wire_only.speedup"], 4.5)

    def test_parse_odbc_streaming_metrics_includes_workload_shape(self) -> None:
        metrics = parse_odbc_streaming_benchmark_metrics(
            "streamQueryBatched: 174.96 ms, rows=2011, chunks=3, "
            "rowsPerSecond=11494, fetchSize=1000, chunkSize=1048576"
        )

        self.assertEqual(metrics["streamQueryBatched.elapsed_ms"], 174.96)
        self.assertEqual(metrics["streamQueryBatched.rows"], 2011.0)
        self.assertEqual(metrics["streamQueryBatched.chunks"], 3.0)
        self.assertEqual(metrics["streamQueryBatched.fetch_size"], 1000.0)
        self.assertEqual(metrics["streamQueryBatched.chunk_size"], 1048576.0)

    def test_resolve_odbc_fast_prefers_locked_published_package(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            project_root = root / "project"
            project_root.mkdir()
            (project_root / "pubspec.lock").write_text(
                'packages:\n  odbc_fast:\n    version: "4.5.1"\n',
                encoding="utf-8",
            )
            package_root = root / "pub-cache" / "hosted" / "pub.dev" / "odbc_fast-4.5.1"
            package_root.mkdir(parents=True)
            (package_root / "pubspec.yaml").write_text("name: odbc_fast\n", encoding="utf-8")

            with patch("tool.py.benchmark_common.PROJECT_ROOT", project_root):
                with patch.dict("os.environ", {"PUB_CACHE": str(root / "pub-cache")}, clear=True):
                    self.assertEqual(resolve_dart_odbc_fast_root(), package_root)


if __name__ == "__main__":
    unittest.main()
