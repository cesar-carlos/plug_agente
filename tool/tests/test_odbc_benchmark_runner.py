from __future__ import annotations

import os
import json
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.py.odbc_benchmark_runner import resolve_benchmark_driver_family, run_odbc_async_benchmark, run_odbc_streaming_benchmark


class OdbcBenchmarkRunnerTests(unittest.TestCase):
    def test_legacy_three_sample_report_cannot_qualify_current_performance(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'pubspec.yaml').write_text('name: fixture\nversion: 5.0.0\n')
            benchmark = root / 'custom.dart'
            benchmark.write_text('void main() {}')
            log = root / 'output.log'
            sample = {'rows': 8000, 'elapsed_ms': 1.25, 'chunks': 8, 'fetch_size': 1000, 'chunk_size': 1048576, 'rows_per_second': 6400000}
            payload = {'benchmark': 'native_odbc_streaming', 'harness_version': 2, 'workload': 'deterministic_8000_rows_v1', 'rows': 8000, 'warmup': 1, 'repeats': 3,
                       'scenarios': [{'scenario': name, **sample, 'samples': [sample.copy() for _ in range(3)]} for name in ('streamQueryBuffer', 'streamQueryBatched')]}
            def fake_run(*_args, **_kwargs):
                log.write_text(json.dumps(payload))
                return 0
            with patch('tool.py.odbc_benchmark_runner.run_streaming', side_effect=fake_run):
                code, _, _ = run_odbc_streaming_benchmark(package_root=root, log_path=log, benchmark_path=benchmark, environment={})
            self.assertEqual(code, 2)

    def test_explicit_matrix_driver_overrides_default_sql_server_preference(self) -> None:
        environment = {
            "ODBC_BENCH_DRIVER_DSN": "Driver={SQL Anywhere 17};ServerName=matrix",
            "ODBC_TEST_DSN_SQL_SERVER": "Driver={ODBC Driver 17 for SQL Server};Server=default",
        }
        self.assertEqual(resolve_benchmark_driver_family(environment), "SQL Anywhere")

    def test_driver_family_uses_the_same_dsn_preference_as_the_runner(self) -> None:
        environment = {
            "ODBC_TEST_DSN": "Driver={SQL Anywhere 17};ServerName=generic",
            "ODBC_TEST_DSN_SQL_SERVER": "Driver={ODBC Driver 17 for SQL Server};Server=benchmark",
        }

        self.assertEqual(resolve_benchmark_driver_family(environment), "SQL Server")

    def test_async_benchmark_uses_a_child_environment_without_leaking_it(self) -> None:
        with tempfile.TemporaryDirectory() as temporary_directory:
            package_root = Path(temporary_directory)
            (package_root / 'pubspec.yaml').write_text('name: fixture\nversion: 5.0.0\n')
            benchmark_file = package_root / "example" / "async_concurrency_benchmark.dart"
            benchmark_file.parent.mkdir()
            benchmark_file.write_text("void main() {}", encoding="utf-8")
            log_path = package_root / "async.log"
            captured_environments: list[dict[str, str]] = []

            def fake_run_streaming(*_args: object, **kwargs: object) -> int:
                captured_environments.append(dict(kwargs["env"]))
                labels = ('workerCount=1', 'workerCount=4', 'workerCount=4 columnar', 'workerCount=4 columnar compressed', 'native pool', 'prepared reuse')
                sample = {'elapsed_ms': 1.5, 'rows': 8000, 'timeouts': 0, 'fallbacks': 0}
                log_path.write_text(json.dumps({'benchmark': 'native_odbc_async', 'harness_version': 2, 'workload': 'deterministic_8000_rows_v1', 'rows': 8000, 'warmup': 1, 'repeats': 9, 'scenarios': [
                    {'scenario': label, **sample, 'encoding': encoding, 'actual_encoding': encoding, 'samples': [{**sample, 'encoding': encoding, 'actual_encoding': encoding}] * 9} for label in labels for encoding in ['columnarCompressed' if label.endswith('compressed') else ('columnar' if label.endswith('columnar') else 'rowMajor')]]}))
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
                        benchmark_path=benchmark_file,
                    )

                self.assertEqual(exit_code, 0)
                self.assertEqual(os.environ["ODBC_TEST_DSN"], "generic-dsn")
                self.assertNotIn("ODBC_BENCH_QUERY", os.environ)

            self.assertEqual(len(captured_environments), 1)
            self.assertEqual(
                captured_environments[0]["ODBC_TEST_DSN"],
                "DRIVER={ODBC Driver 17 for SQL Server};Server=benchmark",
            )
            self.assertNotIn("ODBC_BENCH_QUERY", captured_environments[0])
            with patch.dict(os.environ, {}, clear=True):
                with patch('tool.py.odbc_benchmark_runner.run_streaming', side_effect=fake_run_streaming):
                    gate_code, _, _ = run_odbc_async_benchmark(
                        package_root=package_root, log_path=log_path, benchmark_path=benchmark_file,
                        environment={'BENCHMARK_ENFORCE_ODBC_GATES': '1'},
                    )
                self.assertEqual(gate_code, 3)
                self.assertNotIn('BENCHMARK_ENFORCE_ODBC_GATES', os.environ)

    def test_failed_query_is_not_retried_with_a_smaller_workload(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'pubspec.yaml').write_text('name: fixture\nversion: 5.0.0\n')
            benchmark = root / 'custom.dart'
            benchmark.write_text('void main() {}')
            with patch('tool.py.odbc_benchmark_runner.run_streaming', return_value=1) as run:
                code, _, _ = run_odbc_streaming_benchmark(package_root=root, log_path=root / 'output.log', benchmark_path=benchmark)
            self.assertEqual(code, 1)
            run.assert_called_once()
            self.assertIn('custom.dart', run.call_args.args[0])
            self.assertEqual(run.call_args.kwargs['cwd'], root)

    def test_success_without_streaming_rows_is_inconclusive(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'pubspec.yaml').write_text('name: fixture\nversion: 5.0.0\n')
            benchmark = root / 'custom.dart'
            benchmark.write_text('void main() {}')
            with patch('tool.py.odbc_benchmark_runner.run_streaming', return_value=0):
                code, _, _ = run_odbc_streaming_benchmark(package_root=root, log_path=root / 'output.log', benchmark_path=benchmark)
            self.assertEqual(code, 2)


if __name__ == "__main__":
    unittest.main()
