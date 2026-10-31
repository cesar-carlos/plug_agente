import os
import subprocess
import tempfile
import unittest
from pathlib import Path
from installer import build_installer


@unittest.skipUnless(os.name == "nt", "Requires Windows/Inno Setup")
class InstallerCommandTests(unittest.TestCase):
    def test_blocked_process_is_bounded_and_never_reports_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            fixture = Path(__file__).parent / "fixtures/installer_command_test.iss"
            compiled = subprocess.run([build_installer.find_iscc(), "/Q", f"/O{root}",
                f"/DProductionInstallerDir={build_installer.INSTALLER_DIR}", str(fixture)],
                capture_output=True, text=True, timeout=60)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = root / "result.txt"
            log = root / "test.log"
            subprocess.run([str(root / "installer-command-test.exe"), "/VERYSILENT",
                "/SUPPRESSMSGBOXES", f"/RESULT={result}", f"/LOG={log}"], timeout=25)
            self.assertTrue(result.exists(), log.read_text(encoding="utf-8-sig", errors="replace"))
            self.assertEqual(result.read_text(), "passed")
