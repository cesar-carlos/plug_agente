import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tool.odbc.build_pinned_native import pinned_package, verify_native_bundle


class PinnedNativeTests(unittest.TestCase):
    def test_bundle_must_contain_the_exact_source_built_binary(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            binary = root / 'engine.dll'
            binary.write_bytes(b'qualified')
            bundle = root / 'bundle'
            bundle.mkdir()
            with self.assertRaises(ValueError):
                verify_native_bundle(bundle, binary)
            (bundle / 'engine.dll').write_bytes(b'qualified')
            verify_native_bundle(bundle, binary)
            (bundle / 'engine.dll').write_bytes(b'stale')
            with self.assertRaises(ValueError):
                verify_native_bundle(bundle, binary)
    def test_git_lock_must_match_the_resolved_checkout(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / '.dart_tool').mkdir()
            (root / '.dart_tool/package_config.json').write_text(json.dumps({
                'packages': [{'name': 'odbc_fast', 'rootUri': root.as_uri()}]}))
            (root / 'pubspec.lock').write_text('packages:\n  odbc_fast:\n    source: git\n    description:\n      resolved-ref: "' + 'a' * 40 + '"\nsdks:\n')
            with patch('subprocess.check_output', return_value='b' * 40):
                with self.assertRaisesRegex(ValueError, 'differs'):
                    pinned_package(root)
            with patch('subprocess.check_output', return_value='a' * 40):
                self.assertEqual(pinned_package(root), (root, 'a' * 40))
            (root / 'pubspec.lock').write_text('packages:\n  odbc_fast:\n    source: hosted\nsdks:\n')
            with self.assertRaisesRegex(ValueError, 'Git revision'):
                pinned_package(root)


if __name__ == '__main__':
    unittest.main()
