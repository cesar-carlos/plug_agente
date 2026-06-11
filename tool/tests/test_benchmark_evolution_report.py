from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.benchmark_evolution_report import build_run_report, discover_summaries, main as report_main
from tool.py import benchmark_common


class BenchmarkEvolutionReportTests(unittest.TestCase):
    def test_discover_summaries_sorts_newest_first(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            for run_id in ("20260606_100000", "20260608_120000"):
                run_dir = root / run_id
                run_dir.mkdir()
                (run_dir / "summary.json").write_text("{}", encoding="utf-8")
            discovered = discover_summaries(root)
            self.assertEqual([path.parent.name for path in discovered], ["20260608_120000", "20260606_100000"])

    def test_build_run_report_counts_regressions(self) -> None:
        baseline_metrics = {"transport_pipeline.wall_ms": 100.0}
        summary_path = Path(tempfile.mkdtemp()) / "summary.json"
        summary_path.write_text(
            json.dumps(
                {
                    "run_id": "20260611_140000",
                    "captured_at": "2026-06-11T14:00:00",
                    "suites": [
                        {
                            "id": "transport_pipeline",
                            "kind": "flutter_test",
                            "status": "pass",
                            "metrics": {"wall_ms": 150.0},
                        }
                    ],
                }
            ),
            encoding="utf-8",
        )
        report = build_run_report(summary_path, baseline_metrics, threshold=0.20)
        self.assertEqual(report.regression_count, 1)

    def test_report_cli_lists_runs(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            baseline = root / "baseline.json"
            baseline.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "run_id": "baseline",
                        "suites": [{"id": "transport_pipeline", "metrics": {"wall_ms": 100.0}}],
                    }
                ),
                encoding="utf-8",
            )
            run_dir = root / "results" / "20260611_150000"
            run_dir.mkdir(parents=True)
            (run_dir / "summary.json").write_text(
                json.dumps(
                    {
                        "run_id": "20260611_150000",
                        "captured_at": "2026-06-11T15:00:00",
                        "suites": [{"id": "transport_pipeline", "metrics": {"wall_ms": 105.0}}],
                    }
                ),
                encoding="utf-8",
            )
            with patch.object(benchmark_common, "BASELINE_PATH", baseline):
                with patch.object(benchmark_common, "RESULTS_DIR", root / "results"):
                    exit_code = report_main(["--results-dir", str(root / "results")])
            self.assertEqual(exit_code, 0)


if __name__ == "__main__":
    unittest.main()
