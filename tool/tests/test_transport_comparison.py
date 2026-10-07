import copy
import hashlib
import unittest

from tool.benchmarks.compare_transport_repetitions import compare
from tool.benchmarks.run_transport_comparison import qualify, run_measurement
from tool.benchmarks.measurement_guard import MeasurementGuard, validate_dependency_change, native_identity, file_set_identity
from unittest.mock import patch
from tool.py.benchmark_common import collect_dependency_provenance
from pathlib import Path
import tempfile
import json
import subprocess


def report():
    scenarios = [
        {'case': case, 'requested_compression': mode, 'signed': signed,
         'summary': {'error_count': 0}, 'iterations': 100, 'send_sample_count': 100, 'receive_sample_count': 100, 'original_bytes': 100,
         'wire_bytes': 100, 'effective_compression': 'none',
         'send_p95_us': 100, 'receive_p95_us': 100}
        for case in ('small_sql_repetitive', 'large_sql_low_compressibility', 'large_incompressible_blob')
        for mode in ('none', 'auto', 'gzip') for signed in (False, True)
    ]
    return {'harness_version': 2, 'dart_version': 'test', 'platform': 'test',
            'config': {'iterations': 100, 'warmup_iterations': 10, 'repeats': 9},
            'repetitions': [copy.deepcopy(scenarios) for _ in range(9)],
            'elapsed_us': [1000] * 9, 'rss_peak_bytes': 1000, 'heap_growth_bytes': 100}


class TransportComparisonTests(unittest.TestCase):
    def test_harness_change_invalidates_the_measurement_identity(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'harness.dart').write_text('measure real workload')
            before = file_set_identity(root, ('harness.dart',))
            (root / 'harness.dart').write_text('skip real workload')
            self.assertNotEqual(before, file_set_identity(root, ('harness.dart',)))

    def test_legacy_reference_can_already_be_at_the_staged_path(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / 'native/target/release/engine.dll'
            binary.parent.mkdir(parents=True)
            binary.write_bytes(b'reference artifact')
            output = root / 'results'
            output.mkdir()
            (output / 'control.json').write_text(json.dumps({'complete': True}))
            with patch('tool.benchmarks.run_transport_comparison.subprocess.run', return_value=subprocess.CompletedProcess([], 0)):
                self.assertEqual(run_measurement(root, output, 'control', native_library=binary, legacy=True), {'complete': True})
            self.assertEqual(binary.read_bytes(), b'reference artifact')
            self.assertEqual((root / 'build/odbc-native/pinned/engine.dll').read_bytes(), binary.read_bytes())

    def test_wakefulness_restores_the_previous_execution_state(self):
        from unittest.mock import MagicMock
        kernel = MagicMock()
        kernel.kernel32.SetThreadExecutionState.return_value = 0x80000001
        with patch('tool.benchmarks.measurement_guard.os.name', 'nt'), patch('ctypes.windll', kernel, create=True):
            with MeasurementGuard() as guard:
                guard.largest_gap_seconds = 61
                self.assertTrue(guard.interrupted)
            self.assertEqual(kernel.kernel32.SetThreadExecutionState.call_args_list[-1].args, (0x80000001,))
    def test_same_version_from_a_different_source_is_detected(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            lock = root / 'pubspec.lock'
            lock.write_text('packages:\n  meta:\n    source: hosted\n    version: "1"\nsdks:\n')
            a = collect_dependency_provenance(root)
            lock.write_text('packages:\n  meta:\n    source: git\n    version: "1"\nsdks:\n')
            with self.assertRaises(ValueError):
                validate_dependency_change(a, collect_dependency_provenance(root), allow_odbc=True)
    def test_complete_identical_reports_pass(self):
        self.assertEqual(compare(report(), report())['status'], 'pass')

    def test_missing_heap_is_inconclusive(self):
        candidate = report()
        del candidate['heap_growth_bytes']
        self.assertEqual(compare(report(), candidate)['status'], 'inconclusive')

    def test_measured_zero_heap_growth_obeys_the_existing_limit(self):
        base, candidate = report(), report()
        base['heap_growth_bytes'] = candidate['heap_growth_bytes'] = 0
        self.assertEqual(compare(base, candidate)['status'], 'inconclusive')
        candidate['heap_growth_bytes'] = 1
        result = compare(base, candidate)
        self.assertEqual(result['status'], 'inconclusive')
        self.assertIn('Heap growth exceeds 110% of base', result['failures'])

    def test_only_explicit_odbc_dependency_change_is_allowed(self):
        validate_dependency_change({'odbc_fast': '5'}, {'odbc_fast': 'git:abc'}, allow_odbc=True)
        with self.assertRaises(ValueError):
            validate_dependency_change({'odbc_fast': '5'}, {'odbc_fast': 'git:abc'}, allow_odbc=False)
        with self.assertRaises(ValueError):
            validate_dependency_change({'meta': '1'}, {'meta': '2'}, allow_odbc=True)

    def test_native_provenance_requires_revision_and_hashes_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'native.dll'
            path.write_bytes(b'engine')
            self.assertEqual(len(native_identity(path, 'a' * 40)['sha256']), 64)
            with self.assertRaises(ValueError):
                native_identity(path, 'main')

    def test_published_native_provenance_records_package_and_rejects_changed_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'odbc_engine.dll'
            path.write_bytes(b'published engine')
            manifest = {
                'source': 'pub.dev', 'version': '5.0.1', 'package_sha256': 'a' * 64,
                'url': 'https://github.com/cesar-carlos/dart_odbc_fast/releases/download/v5.0.1/odbc_engine.dll',
                'sha256': hashlib.sha256(path.read_bytes()).hexdigest(),
            }
            (path.parent / 'manifest.json').write_text(json.dumps(manifest))
            identity = native_identity(path)
            self.assertEqual(identity['version'], '5.0.1')
            self.assertEqual(identity['package_sha256'], 'a' * 64)
            self.assertNotIn('revision', identity)
            path.write_bytes(b'stale engine')
            with self.assertRaisesRegex(ValueError, 'differs from the binary'):
                native_identity(path)

    def test_missing_published_provenance_cannot_qualify_a_native_artifact(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'odbc_engine.dll'
            path.write_bytes(b'engine without provenance')
            with self.assertRaises(FileNotFoundError):
                native_identity(path)

    def test_each_existing_limit_is_preserved(self):
        for field in ('latency', 'throughput', 'heap'):
            with self.subTest(field=field):
                candidate = report()
                if field == 'latency':
                    for rows in candidate['repetitions']:
                        rows[0]['receive_p95_us'] = 106
                elif field == 'throughput':
                    candidate['elapsed_us'] = [1200] * 9
                else:
                    candidate['heap_growth_bytes'] = 111
                self.assertEqual(compare(report(), candidate)['status'], 'fail')

    def test_missing_scenario_or_nonfinite_measurement_is_rejected(self):
        for invalid in ('missing', 'nan', 'samples'):
            candidate = report()
            if invalid == 'missing':
                candidate['repetitions'][0].pop()
            elif invalid == 'nan':
                candidate['repetitions'][0][0]['send_p95_us'] = float('nan')
            else:
                candidate['config']['iterations'] = 20
            with self.assertRaises(ValueError):
                compare(report(), candidate)

    def test_noisy_identical_code_control_prevents_a_regression_claim(self):
        valid = compare(report(), report())
        control = {**valid, 'failures': ['latency noise']}
        self.assertEqual(qualify(control, valid, valid)['status'], 'inconclusive')

    def test_either_order_failing_is_not_approved(self):
        valid = compare(report(), report())
        failed = {**valid, 'failures': ['regression']}
        self.assertEqual(qualify(valid, valid, failed)['status'], 'fail')


if __name__ == '__main__':
    unittest.main()
