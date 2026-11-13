import hashlib
from pathlib import Path
import subprocess
import tempfile
import unittest

from tool.release.prepared_source import prepare, require_tree, verify_installer


class PreparedSourceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.git('init', '-q')
        self.git('config', 'user.name', 'Fixture')
        self.git('config', 'user.email', 'fixture@example.invalid')
        self.git('config', 'core.autocrlf', 'false')
        (self.root / 'pubspec.yaml').write_text('version: 1.0.0+1\n', encoding='utf-8')
        (self.root / 'installer').mkdir()
        (self.root / 'lib/core/constants').mkdir(parents=True)
        (self.root / 'installer/setup.iss').write_text('original', encoding='utf-8')
        (self.root / 'lib/core/constants/app_version.g.dart').write_text('original', encoding='utf-8')
        (self.root / 'installer/update_version.py').write_text(
            "from pathlib import Path\n"
            "version = Path('pubspec.yaml').read_text().strip()\n"
            "Path('installer/setup.iss').write_text(version)\n"
            "Path('lib/core/constants/app_version.g.dart').write_text(version)\n",
            encoding='utf-8',
        )
        self.git('add', '.')
        self.git('commit', '-qm', 'fixture')
        self.commit = self.git('rev-parse', 'HEAD')

    def git(self, *args):
        return subprocess.check_output(['git', *args], cwd=self.root, text=True,
                                       stderr=subprocess.PIPE).strip()

    def test_independent_preparations_produce_identical_tree_without_commit(self):
        first = prepare(self.root, '1.2.3+4')
        self.assertEqual(self.git('rev-parse', 'HEAD'), self.commit)
        self.git('reset', '--hard', self.commit)
        second = prepare(self.root, '1.2.3+4')
        require_tree(first, second)
        self.assertEqual(self.git('show', ':pubspec.yaml'), 'version: 1.2.3+4')

    def test_different_version_cannot_be_promoted_as_tested_source(self):
        first = prepare(self.root, '1.2.3+4')
        self.git('reset', '--hard', self.commit)
        second = prepare(self.root, '1.2.3+5')
        with self.assertRaisesRegex(ValueError, 'source tree'):
            require_tree(first, second)

    def test_invalid_version_leaves_source_unchanged(self):
        with self.assertRaisesRegex(ValueError, 'FULL_VERSION'):
            prepare(self.root, '1.2.3;bad')
        self.assertEqual(self.git('status', '--porcelain'), '')

    def test_dirty_source_is_rejected(self):
        (self.root / 'pubspec.yaml').write_text('version: 9.9.9+9\n')
        with self.assertRaises(subprocess.CalledProcessError):
            prepare(self.root, '1.2.3+4')

    def test_empty_tree_evidence_is_rejected(self):
        with self.assertRaises(ValueError):
            require_tree('', '')

    def test_downloaded_installer_must_match_build_digest(self):
        path = self.root / 'installer.exe'
        path.write_bytes(b'validated installer')
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        verify_installer(path, digest)
        path.write_bytes(b'tampered installer')
        with self.assertRaisesRegex(ValueError, 'digest mismatch'):
            verify_installer(path, digest)
        with self.assertRaises(ValueError):
            verify_installer(path, '')


if __name__ == '__main__':
    unittest.main()
