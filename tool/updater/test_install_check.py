import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path


@unittest.skipUnless(os.name == "nt", "Native installation checks require Windows")
class NativeInstallationCheckTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        configured = os.environ.get("PLUG_INSTALL_CHECK_BUNDLE")
        cls.bundle = Path(configured or "build/windows/x64/runner/Release").resolve()
        cls.executable = cls.bundle / "plug_install_check.exe"
        if not cls.executable.is_file():
            if configured:
                raise AssertionError("The configured installation-check bundle is missing")
            raise unittest.SkipTest("Build the Windows release before testing the native check")

    def run_check(self, executable, *arguments):
        return subprocess.run([str(executable), *map(str, arguments)],
                              capture_output=True, text=True, encoding="utf-8", timeout=45)

    def test_bundled_flutter_engine_dart_entrypoint_plugins_and_assets_can_start(self):
        result = self.run_check(self.executable, "--core")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("code=core_ready", result.stdout)

    def test_missing_application_is_critical_even_without_a_system_vc_runtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            executable = Path(temporary) / self.executable.name
            shutil.copy2(self.executable, executable)
            result = self.run_check(executable, "--core")
            self.assertEqual(result.returncode, 3, result.stdout)
            self.assertIn("core_file_missing", result.stdout)

    def test_user_data_probe_reads_writes_and_cleans_up_its_own_file(self):
        with tempfile.TemporaryDirectory() as temporary:
            result = self.run_check(self.executable, "--data", temporary)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(list(Path(temporary).iterdir()), [])

    def test_missing_data_directory_warns_without_creating_it(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "missing"
            result = self.run_check(self.executable, "--data", path)
            self.assertEqual(result.returncode, 2, result.stdout)
            self.assertIn("data_directory_missing", result.stdout)
            self.assertFalse(path.exists())

    def test_odbc_probe_identifies_driver_availability_without_connecting(self):
        result = self.run_check(self.executable, "--odbc")
        self.assertIn(result.returncode, (0, 2), result.stdout)
        self.assertTrue("code=odbc_" in result.stdout, result.stdout)
        if result.returncode == 0:
            self.assertIn("database_connection=not_tested", result.stdout)
