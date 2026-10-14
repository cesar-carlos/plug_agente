import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tool.benchmarks import prepare_transport_comparison as comparison


class PrepareTransportComparisonTests(unittest.TestCase):
    def test_hosted_baseline_uses_its_locked_published_native_asset(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary).resolve()
            (base / 'pubspec.lock').write_text(
                'packages:\n  odbc_fast:\n    source: hosted\n    version: "5.0.1"\nsdks:\n')
            library = base / 'libodbc_engine.so'
            (base / 'manifest.json').write_text(json.dumps({'source': 'pub.dev', 'version': '5.0.1'}))
            with patch.object(comparison, 'prepare_native_library', return_value=library) as prepare, \
                 patch.object(comparison, 'build_pinned_native') as build, \
                 patch.object(comparison.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
                self.assertEqual(comparison.main(['--base-dir', str(base), '--output-dir', str(base / 'out')]), 0)
            self.assertEqual([call.args[0] for call in prepare.call_args_list], [base, comparison.ROOT])
            build.assert_not_called()
            command = run.call_args.args[0]
            self.assertNotIn('--base-odbc-revision', command)
            self.assertEqual(command[command.index('--base-native-library') + 1], str(library))

    def test_git_baseline_keeps_its_verified_source_revision(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary).resolve()
            (base / 'pubspec.lock').write_text('packages:\n  odbc_fast:\n    source: git\nsdks:\n')
            library = base / 'libodbc_engine.so'
            revision = 'a' * 40
            (base / 'manifest.json').write_text(json.dumps({'revision': revision}))
            with patch.object(comparison, 'prepare_native_library', return_value=library), \
                 patch.object(comparison, 'build_pinned_native', return_value=library) as build, \
                 patch.object(comparison.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
                self.assertEqual(comparison.main(['--base-dir', str(base), '--output-dir', str(base / 'out')]), 0)
            build.assert_called_once_with(base)
            command = run.call_args.args[0]
            self.assertEqual(command[command.index('--base-odbc-revision') + 1], revision)

    def test_native_verification_failure_stops_before_measurement(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            (base / 'pubspec.lock').write_text('packages:\n  odbc_fast:\n    source: hosted\nsdks:\n')
            with patch.object(comparison, 'prepare_native_library', side_effect=ValueError('checksum mismatch')), \
                 patch.object(comparison.subprocess, 'run') as run:
                with self.assertRaisesRegex(ValueError, 'checksum mismatch'):
                    comparison.main(['--base-dir', str(base), '--output-dir', str(base / 'out')])
            self.assertEqual(run.call_count, 1)


if __name__ == '__main__':
    unittest.main()
