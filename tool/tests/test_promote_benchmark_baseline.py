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
from tool.tests.test_transport_comparison import report
from tool.benchmarks.compare_transport_repetitions import compare
from tool.benchmarks.run_transport_comparison import qualify
from tool.benchmarks.run_benchmark_suite import required_metric_keys


def valid_summary():
    metrics = {key: 10 for key in required_metric_keys('transport_pipeline')}
    identity = {'commit_sha': 'measured', 'source_sha256': 'a' * 64}
    result = compare(report(), report())
    comparison = qualify(result, result, result)
    comparison['candidate'] = identity
    return {'schema_version': 2, 'qualification': 'pass', 'comparison': comparison,
            'dependencies': {'test': '1.0'}, 'machine': {'dart_version': 'test', 'flutter_version': 'test', 'dependencies_sha256': 'test', 'host_fingerprint': 'test'},
            'git': {**identity, 'branch': 'main', 'dirty': False},
            'run_id': '20260611_120000', 'suites': [{'id': 'transport_pipeline',
            'kind': 'flutter_test', 'status': 'pass', 'metrics': metrics,
            'metric_metadata': {key: benchmark_common.metric_metadata(key) for key in metrics},
            'comparison_identity': {'benchmark_profile': 'test_v2'}}]}



class PromoteBenchmarkBaselineTests(unittest.TestCase):
    def test_partial_metrics_or_controlled_comparison_cannot_be_promoted(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'summary.json'
            for missing in ('control', 'scenario', 'metric'):
                summary = valid_summary()
                if missing == 'control':
                    del summary['comparison']['control']
                elif missing == 'scenario':
                    summary['comparison']['forward']['scenarios'].pop()
                else:
                    summary['suites'][0]['metrics'].pop(next(iter(summary['suites'][0]['metrics'])))
                source.write_text(json.dumps(summary))
                with self.assertRaises(ValueError):
                    promote_summary(source, dry_run=True)
    def test_legacy_failed_or_unqualified_runs_cannot_replace_baseline(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / 'summary.json'
            for summary in (
                {'schema_version': 1, 'suites': []},
                {'schema_version': 2, 'qualification': 'fail', 'comparison': {'status': 'pass'}},
                {'schema_version': 2, 'qualification': 'pass', 'comparison': {'status': 'inconclusive'}},
                {'schema_version': 2, 'qualification': 'pass', 'comparison': {'status': 'pass'}, 'suites': []},
            ):
                source.write_text(json.dumps(summary))
                with self.assertRaises(ValueError):
                    promote_summary(source, dry_run=True)

    def test_promote_summary_sets_baseline_metadata(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            source = root / "summary.json"
            source.write_text(
                json.dumps(
                    valid_summary(),
                ),
                encoding="utf-8",
            )
            baseline_path = root / "baseline" / "summary.json"
            with patch.object(benchmark_common, "BASELINE_PATH", baseline_path, create=False):
                destination = promote_summary(source)
            payload = json.loads(destination.read_text(encoding="utf-8"))
            self.assertEqual(payload["run_id"], "baseline")
            self.assertEqual(payload["git"]["branch"], "main")

    def test_promote_cli_uses_latest_results(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            results_dir = root / "results" / "20260611_130000"
            results_dir.mkdir(parents=True)
            summary = valid_summary()
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
