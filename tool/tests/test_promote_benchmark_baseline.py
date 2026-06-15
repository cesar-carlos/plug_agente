from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.benchmarks.promote_benchmark_baseline import main as promote_main, promote_summary
from tool.py import benchmark_common


class PromoteBenchmarkBaselineTests(unittest.TestCase):
    def test_promote_summary_sets_baseline_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "summary.json"
            source.write_text(
                json.dumps(
                    {
                        "schema_version": 1,
                        "run_id": "20260611_120000",
                        "suites": [{"id": "transport_pipeline", "kind": "flutter_test", "status": "pass"}],
                    }
                ),
                encoding="utf-8",
            )
            baseline_path = root / "baseline" / "summary.json"
            with patch.object(benchmark_common, "BASELINE_PATH", baseline_path, create=False):
                destination = promote_summary(source)
            payload = json.loads(destination.read_text(encoding="utf-8"))
            self.assertEqual(payload["run_id"], "baseline")
            self.assertEqual(payload["git"]["branch"], "baseline")

    def test_promote_cli_uses_latest_results(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            results_dir = root / "results" / "20260611_130000"
            results_dir.mkdir(parents=True)
            summary = {
                "schema_version": 1,
                "run_id": "20260611_130000",
                "suites": [{"id": "transport_pipeline", "kind": "flutter_test", "status": "pass"}],
            }
            (results_dir / "summary.json").write_text(json.dumps(summary), encoding="utf-8")
            baseline_path = root / "baseline" / "summary.json"
            with (
                patch.object(benchmark_common, "RESULTS_DIR", root / "results"),
                patch.object(benchmark_common, "BASELINE_PATH", baseline_path),
            ):
                exit_code = promote_main([])
            self.assertEqual(exit_code, 0)
            self.assertTrue(baseline_path.is_file())


if __name__ == "__main__":
    unittest.main()
