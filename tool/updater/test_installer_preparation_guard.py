import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from installer import build_installer


@unittest.skipUnless(os.name == "nt", "Requires Windows and Inno Setup")
class InstallationGuardTests(unittest.TestCase):
    def test_real_guard_api_and_preparation_do_not_replay_shutdown(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = (build_installer.INSTALLER_DIR / "installation_preparation.iss").read_text(encoding="utf-8")
            source = source.replace("{app}", "{tmp}\\guard-app")
            source = source.replace("ExtractTemporaryFile(", "FixtureExtractTemporaryFile(")
            production = root / "production.iss"
            production.write_text(source, encoding="utf-8")
            fixture = Path(__file__).parent / "fixtures/installer_preparation_guard_test.iss"
            compile_result = subprocess.run([build_installer.find_iscc(), "/Q", f"/O{root}",
                f"/DTestProductionFile={production}", str(fixture)], capture_output=True, text=True, timeout=60)
            self.assertEqual(compile_result.returncode, 0, compile_result.stdout + compile_result.stderr)
            for case in ("existing", "new", "existing_guard", "guard_directory", "manual_closure"):
                with self.subTest(case=case):
                    result = root / f"{case}.result"
                    log = root / f"{case}.log"
                    subprocess.run([str(root / "installer-preparation-guard-test.exe"),
                        "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", f"/CASE={case}",
                        f"/RESULT={result}", f"/LOG={log}"], capture_output=True, timeout=60)
                    self.assertTrue(result.exists(), log.read_text(encoding="utf-8-sig", errors="replace"))
                    self.assertEqual(result.read_text(), "passed")
