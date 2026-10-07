import hashlib
import json
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tool.odbc import prepare_package_native as native


class PublishedNativeTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.package = self.root / 'published-package'
        self.package.mkdir()
        (self.package / 'pubspec.yaml').write_text('name: odbc_fast\nversion: 5.0.1\n')
        (self.root / '.dart_tool').mkdir()
        (self.root / '.dart_tool/package_config.json').write_text(json.dumps({
            'packages': [{'name': 'odbc_fast', 'rootUri': self.package.as_uri()}]}))
        (self.root / 'pubspec.lock').write_text(
            'packages:\n  odbc_fast:\n    description:\n      name: odbc_fast\n'
            '      sha256: "' + 'a' * 64 + '"\n      url: "https://pub.dev"\n'
            '    source: hosted\n    version: "5.0.1"\nsdks:\n')
        self.binary = b'published engine'
        self.digest = hashlib.sha256(self.binary).hexdigest()

    def fake_download(self, url, destination, limit):
        content = (self.digest + '  odbc_engine.dll\n').encode() if url.endswith('.sha256') else self.binary
        destination.write_bytes(content)

    def test_prepares_the_locked_published_release_without_compiling_source(self):
        with patch.object(native, 'download', side_effect=self.fake_download) as download:
            binary = native.prepare_native_library(self.root)
        self.assertEqual(binary.read_bytes(), self.binary)
        self.assertTrue(all('/releases/download/v5.0.1/' in call.args[0] for call in download.call_args_list))
        manifest = json.loads((binary.parent / 'manifest.json').read_text())
        self.assertEqual(manifest['source'], 'pub.dev')
        self.assertEqual(manifest['version'], '5.0.1')
        self.assertEqual(manifest['package_sha256'], 'a' * 64)
        with patch.object(native, 'download') as download:
            self.assertEqual(native.prepare_native_library(self.root), binary)
            download.assert_not_called()

    def test_altered_download_is_rejected_and_partial_files_are_removed(self):
        def altered(url, destination, limit):
            self.fake_download(url, destination, limit)
            if not url.endswith('.sha256'):
                destination.write_bytes(b'altered engine')
        with patch.object(native, 'download', side_effect=altered):
            with self.assertRaisesRegex(ValueError, 'SHA-256 mismatch'):
                native.prepare_native_library(self.root)
        self.assertFalse(list(self.root.rglob('*.part')))
        self.assertFalse(list(self.root.rglob('manifest.json')))

    def test_invalid_checksum_fails_before_downloading_the_binary(self):
        with patch.object(native, 'download', side_effect=lambda url, dest, limit: dest.write_bytes(b'invalid')) as download:
            with self.assertRaisesRegex(ValueError, 'checksum is invalid'):
                native.prepare_native_library(self.root)
            self.assertEqual(download.call_count, 1)

    def test_cached_binary_tampering_is_not_silently_accepted(self):
        with patch.object(native, 'download', side_effect=self.fake_download):
            binary = native.prepare_native_library(self.root)
        binary.write_bytes(b'stale engine')
        with self.assertRaisesRegex(ValueError, 'differs from its manifest'):
            native.prepare_native_library(self.root)

    def test_resolved_package_must_match_the_lock_version(self):
        (self.package / 'pubspec.yaml').write_text('version: 5.0.0\n')
        with self.assertRaisesRegex(ValueError, 'differs from pubspec.lock'):
            native.locked_package(self.root)

    def test_git_checkout_is_rejected_by_the_published_build_path(self):
        path = self.root / 'pubspec.lock'
        path.write_text(path.read_text().replace('source: hosted', 'source: git'))
        with self.assertRaisesRegex(ValueError, 'published pub.dev'):
            native.locked_package(self.root)


if __name__ == '__main__':
    unittest.main()
