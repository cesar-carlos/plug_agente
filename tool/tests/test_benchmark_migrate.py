from __future__ import annotations

import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.migrate_benchmark_logs import discover_legacy_summaries, main as migrate_main
from tool.py.benchmark_migrate import migrate_legacy_summary


class BenchmarkMigrateTests(unittest.TestCase):
    def test_migrate_legacy_summary_strips_secrets(self) -> None:
        legacy = {
            "run_timestamp": "20260608_084431",
            "config": {
                "ODBC_POOL_SIZE": 8,
                "API_TEST_BASE_URL": "http://31.97.29.223:3000/",
                "sqlServer_override": "ODBC_E2E_RPC_DSN set from ODBC_TEST_DSN_SQL_SERVER",
            },
            "results": [
                {
                    "test": "odbc_dml_stress_live_e2e",
                    "driver": "sqlServer",
                    "status": "pass",
                    "total_ms": 1449,
                    "rows": 100,
                }
            ],
        }
        summary = migrate_legacy_summary(legacy)
        self.assertEqual(summary["schema_version"], 1)
        self.assertEqual(summary["run_id"], "20260608_084431")
        self.assertNotIn("api_test_base_url", summary["env_flags"])
        self.assertEqual(summary["suites"][0]["id"], "odbc_dml_stress_live_e2e.sqlServer")
        self.assertEqual(summary["suites"][0]["metrics"]["total_ms"], 1449.0)

    def test_migrate_cli_writes_history(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source_dir = root / "benchmark_logs" / "20260606_122349"
            source_dir.mkdir(parents=True)
            source_dir.joinpath("summary.json").write_text(
                json.dumps(
                    {
                        "run_timestamp": "20260606_122349",
                        "config": {"ODBC_POOL_SIZE": 8},
                        "results": [
                            {
                                "test": "odbc_dml_stress_live_e2e",
                                "driver": "sqlAnywhere",
                                "status": "pass",
                                "total_ms": 1564,
                            }
                        ],
                    }
                ),
                encoding="utf-8",
            )
            output_dir = root / "benchmarks" / "history"
            exit_code = migrate_main(
                [
                    "--source-dir",
                    str(source_dir.parent),
                    "--output-dir",
                    str(output_dir),
                ]
            )
            self.assertEqual(exit_code, 0)
            destination = output_dir / "20260606_122349" / "summary.json"
            self.assertTrue(destination.is_file())
            payload = json.loads(destination.read_text(encoding="utf-8"))
            self.assertEqual(payload["run_id"], "20260606_122349")

    def test_discover_legacy_summaries(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            (root / "20260606_115942").mkdir()
            (root / "20260606_115942" / "summary.json").write_text("{}", encoding="utf-8")
            discovered = discover_legacy_summaries(root)
            self.assertEqual(len(discovered), 1)


if __name__ == "__main__":
    unittest.main()
