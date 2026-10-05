import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from installer import build_installer


@unittest.skipUnless(os.name == "nt", "Pascal installer tests require Windows and Inno Setup")
class InstallerRecoveryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        try:
            compiler = build_installer.find_iscc()
        except SystemExit as error:
            raise unittest.SkipTest(str(error)) from error
        cls.temporary = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.temporary.cleanup)
        cls.root = Path(cls.temporary.name)
        cls.installer = build_installer.INSTALLER_DIR
        setup = (cls.installer / "setup.iss").read_text(encoding="utf-8")
        messages = setup.rsplit("[CustomMessages]", 1)[1].split("[Tasks]", 1)[0]
        messages_file = cls.root / "messages.iss"
        messages_file.write_text(messages, encoding="utf-8")
        fixture = Path(__file__).parent / "fixtures" / "installer_recovery_test.iss"
        compiled = subprocess.run(
            [compiler, "/Q", f"/O{cls.root}", f"/DProductionInstallerDir={cls.installer}",
             f"/DTestMessagesFile={messages_file}", str(fixture)],
            capture_output=True, text=True, timeout=60,
        )
        if compiled.returncode != 0:
            raise AssertionError(compiled.stdout + compiled.stderr)
        cls.executable = cls.root / "installer-recovery-test.exe"

    def run_case(self, case, *, language="english"):
        report = self.root / f"{case}-{language}.log"
        result = self.root / f"{case}-{language}.result"
        arguments = [str(self.executable), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART",
                     f"/CASE={case}", f"/RESULT={result}", f"/REPORT={report}", f"/LANG={language}"]
        if case == "optional_repair_mode":
            arguments.append("/REPAIR=optional")
        subprocess.run(
            arguments,
            capture_output=True, text=True, timeout=60,
        )
        # InitializeSetup returns False after the assertions, before any installation.
        self.assertTrue(result.is_file(), f"Pascal assertions failed for {case}")
        self.assertEqual(result.read_text(), "passed")
        return report

    def test_optional_preparation_failure_continues_without_privileged_updater_copying(self):
        report = self.run_case("initial_preparation_failure")
        contents = report.read_text(encoding="utf-8-sig")
        self.assertIn("missing optional dependency", contents)
        self.assertIn("Required action:", contents)
        self.assertIn("Use manual updates", contents)

    def test_existing_updater_preparation_failure_remains_critical(self):
        self.run_case("existing_updater_preparation_failure")

    def test_failure_policy_keeps_optional_features_and_data_access_recoverable(self):
        self.run_case("failure_policy")

    def test_a_core_that_cannot_start_is_a_critical_failure(self):
        self.run_case("core_failure")

    def test_repair_requires_matching_build_channel_privilege_and_manual_execution(self):
        self.run_case("optional_repair_identity")

    def test_optional_repair_skips_copying_the_application(self):
        self.run_case("optional_repair_mode")

    def test_missing_driver_report_identifies_resource_impact_code_and_action(self):
        report = self.run_case("data_access_warning")
        contents = report.read_text(encoding="utf-8-sig")
        for expected in ("odbc_driver_missing", "Affected resource: ODBC x64",
                         "Impact: database connections unavailable", "install database driver"):
            self.assertIn(expected, contents)

    def test_service_update_preparation_failure_remains_critical(self):
        self.run_case("service_update_preparation_failure")

    def test_enrollment_failure_continues_only_after_confirmed_revocation(self):
        report = self.run_case("failed_enrollment_recovered")
        self.assertIn("feed_keys_unavailable", report.read_text(encoding="utf-8-sig"))

    def test_failed_revocation_remains_a_critical_failure(self):
        self.run_case("failed_enrollment_cleanup_failure")

    def test_metadata_failure_preserves_successful_revocation_and_reports_both_problems(self):
        report = self.run_case("authorization_metadata_failure")
        contents = report.read_text(encoding="utf-8-sig")
        self.assertIn("Authorized=0", contents)
        self.assertIn("feed_keys_unavailable", contents)

    def test_report_write_failure_uses_a_persistent_fallback(self):
        report = self.run_case("report_write_failure_fallback")
        contents = report.read_text(encoding="utf-8-sig")
        self.assertIn("repair the optional feature", contents)
        self.assertIn("report could not be saved", contents)

    def test_clean_installation_does_not_create_or_open_an_error_report(self):
        report = self.run_case("clean_installation")
        self.assertFalse(report.exists())

    def test_portuguese_report_preserves_unicode_and_localized_repair_instructions(self):
        report = self.run_case("failed_enrollment_recovered", language="brazilianportuguese")
        contents = report.read_text(encoding="utf-8-sig")
        self.assertIn("Ajuste necessário:", contents)
        self.assertIn("Use atualizações manuais", contents)
        self.assertIn("feed_keys_unavailable", contents)
