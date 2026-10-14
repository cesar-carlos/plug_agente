import os
import re
import subprocess
import tempfile
import unittest
from pathlib import Path

from installer import build_installer


@unittest.skipUnless(os.name == "nt", "Requires Windows and Inno Setup")
class ManualUpgradeTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            compiler = build_installer.find_iscc()
        except SystemExit as error:
            raise unittest.SkipTest(str(error)) from error
        cls.temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        installer = build_installer.INSTALLER_DIR
        setup = (installer / "setup.iss").read_text(encoding="utf-8")
        messages = cls.root / "messages.iss"
        messages.write_text(setup.rsplit("[CustomMessages]", 1)[1].split("[Tasks]", 1)[0], encoding="utf-8")
        # Execute the actual installer orchestration; replace only Windows/UI I/O.
        functions = []
        for name in ("UpdaterExists", "WantsAutomaticUpdates", "ShouldInstallUpdaterHost",
                     "ShouldInstallUpdaterClient", "ShouldInstallUpdaterWorker",
                     "ConfigureUpdaterAuthorization", "PrepareToInstall"):
            match = re.search(rf"^(?:function|procedure) {name}\b.*?(?=^(?:function|procedure) |\Z)",
                              setup, re.M | re.S)
            if match is None:
                raise AssertionError(f"Missing production function: {name}")
            functions.append(match.group())
        source = "\n".join(functions)
        for name in ("IsAdminInstallMode", "WizardSilent", "WizardIsTaskSelected",
                     "RegQueryDWordValue", "FileExists", "ExtractTemporaryFile"):
            source = re.sub(rf"\b{name}\b", f"Fixture{name}", source)
        source = source.replace("function PrepareToInstall(", "function RunPreparation(")
        production = cls.root / "production.iss"
        production.write_text(source, encoding="utf-8")
        fixture = Path(__file__).parent / "fixtures" / "installer_manual_upgrade_test.iss"
        result = subprocess.run([compiler, "/Q", f"/O{cls.root}",
                                 f"/DProductionInstallerDir={installer}",
                                 f"/DTestMessagesFile={messages}", f"/DTestProductionFile={production}",
                                 str(fixture)], capture_output=True, text=True, timeout=60)
        if result.returncode:
            raise AssertionError(result.stdout + result.stderr)
        cls.executable = cls.root / "installer-manual-upgrade-test.exe"

    def test_manual_upgrade_from_enabled_legacy_updater(self):
        for case in ("manual", "missing_client", "retry_after_contract_error",
                     "upgrade_flag_unchecked", "active_operation", "revocation_failure"):
            with self.subTest(case=case):
                result = self.root / f"{case}.result"
                log = self.root / f"{case}.log"
                arguments = [str(self.executable), "/VERYSILENT", "/SUPPRESSMSGBOXES",
                             "/NORESTART", f"/CASE={case}", f"/RESULT={result}", f"/LOG={log}"]
                if case == "upgrade_flag_unchecked":
                    arguments.append("/UPGRADEUPDATERHOST=1")
                subprocess.run(arguments, capture_output=True, timeout=60)
                self.assertTrue(result.exists(), log.read_text(encoding="utf-8-sig", errors="replace") if log.exists() else case)
                self.assertEqual(result.read_text(), "passed")
