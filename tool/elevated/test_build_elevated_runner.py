import importlib.util
from pathlib import Path
import tempfile
import unittest

_SCRIPT = Path(__file__).with_name('build_elevated_runner.py')
_SPEC = importlib.util.spec_from_file_location('elevated_build', _SCRIPT)
builder = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(builder)


class FlatHelperBuildTest(unittest.TestCase):
    def test_flat_package_keeps_source_hooks_unchanged_and_uses_a_dedicated_library(self):
        source = builder.PACKAGE_DIR
        original = (source / 'pubspec.yaml').read_bytes()
        sidecar = builder._sqlite_sidecar_name(source)
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / 'private-package'
            builder._prepare_flat_package(source, destination,
                                          builder.PROJECT_ROOT / 'packages/windows_action_runtime', sidecar)
            config = (destination / 'pubspec.yaml').read_text(encoding='utf-8')
            self.assertIn('source: system', config)
            self.assertIn('name_windows: plug_agente_elevated_sqlite3', config)
            self.assertNotIn('../../packages/windows_action_runtime', config)
            self.assertEqual((source / 'pubspec.yaml').read_bytes(), original)
            self.assertEqual((source / 'pubspec.lock').read_bytes(), (destination / 'pubspec.lock').read_bytes())

    def test_cleanup_refuses_an_external_directory(self):
        with tempfile.TemporaryDirectory() as temporary:
            sentinel = Path(temporary) / 'keep.txt'
            sentinel.write_text('keep')
            with self.assertRaises(ValueError):
                builder._remove_private_build_directory(Path(temporary))
            self.assertTrue(sentinel.is_file())

    def test_packaging_keeps_the_application_sqlite_intact(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            release = root / 'Release'
            release.mkdir()
            (release / 'sqlite3.dll').write_bytes(b'application sqlite')
            executable = root / 'helper.exe'
            executable.write_bytes(b'helper')
            sqlite = root / 'sqlite3.dll'
            sqlite.write_bytes(b'helper sqlite')
            sidecar = builder._sqlite_sidecar_name(builder.PACKAGE_DIR)
            builder._install_flat_helper(executable, sqlite, release, sidecar)
            self.assertEqual((release / 'sqlite3.dll').read_bytes(), b'application sqlite')
            self.assertEqual((release / sidecar).read_bytes(), b'helper sqlite')
            with self.assertRaises(ValueError):
                builder._install_flat_helper(executable, sqlite, release, 'sqlite3.dll')


if __name__ == '__main__':
    unittest.main()
