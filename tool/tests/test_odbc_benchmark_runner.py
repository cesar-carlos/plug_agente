from __future__ import annotations

import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.py.odbc_benchmark_runner import resolve_benchmark_driver_family, run_odbc_async_benchmark


class OdbcBenchmarkRunnerTests(unittest.TestCase):
    def test_driver_family_uses_the_same_dsn_preference_as_the_runner(self) -> None:
        environment = {
            "ODBC_TEST_DSN": "Driver={SQL Anywhere 17};ServerName=generic",
            "ODBC_TEST_DSN_SQL_SERVER": "Driver={ODBC Driver 17 for SQL Server};Server=benchmark",
        }

        self.assertEqual(resolve_benchmark_driver_family(environment), "SQL Server")

    def test_async_benchmark_uses_a_child_environment_without_leaking_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            package_root = Path(temporary_directory)
            benchmark_file = package_root / "example" / "async_concurrency_benchmark.dart"
            benchmark_file.parent.mkdir()
            benchmark_file.write_text("void main() {}", encoding="utf-8")
            log_path = package_root / "async.log"
            captured_environments: list[dict[str, str]] = []

            def fake_run_streaming(*_args: object, **kwargs: object) -> int:
                captured_environments.append(dict(kwargs["env"]))
                return 0

            with patch.dict(
                os.environ,
                {
                    "ODBC_TEST_DSN": "generic-dsn",
                    "ODBC_TEST_DSN_SQL_SERVER": "DRIVER={ODBC Driver 17 for SQL Server};Server=benchmark",
                    "ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER": "SELECT benchmark",
                },
                clear=True,
            ):
                with patch("tool.py.odbc_benchmark_runner.run_streaming", side_effect=fake_run_streaming):
                    exit_code, _, _ = run_odbc_async_benchmark(
                        package_root=package_root,
                        log_path=log_path,
                    )

                self.assertEqual(exit_code, 0)
                self.assertEqual(os.environ["ODBC_TEST_DSN"], "generic-dsn")
                self.assertNotIn("ODBC_BENCH_QUERY", os.environ)

            self.assertEqual(len(captured_environments), 1)
            self.assertEqual(
                captured_environments[0]["ODBC_TEST_DSN"],
                "DRIVER={ODBC Driver 17 for SQL Server};Server=benchmark",
            )
            self.assertEqual(captured_environments[0]["ODBC_BENCH_QUERY"], "SELECT benchmark")


if __name__ == "__main__":
    unittest.main()
