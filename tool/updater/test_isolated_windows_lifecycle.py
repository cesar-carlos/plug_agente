import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tool.updater import validate_isolated_windows_lifecycle as validation


class IsolatedLifecycleTests(unittest.TestCase):
    def test_host_probe_uses_only_registration_metadata_and_never_opens_installed_state(self):
        metadata = {"startup": None, "protocol": None, "updater_authorized": None}
        forbidden = AssertionError("An isolated fixture must not read operational state")
        with patch.object(validation, "registry_snapshot", return_value=metadata), \
                patch.object(validation, "installation_paths", side_effect=forbidden, create=True), \
                patch.object(validation, "configured_profile_digest", side_effect=forbidden, create=True), \
                patch.object(validation, "updater_snapshot", side_effect=forbidden, create=True), \
                patch.object(validation, "sha256", side_effect=forbidden):
            self.assertEqual(validation.host_snapshot(), {"registry": metadata})

    def test_missing_registration_is_allowed_but_registry_access_failure_is_not_hidden(self):
        forbidden = AssertionError("An isolated fixture must not read operational state")
        with patch.object(validation, "installation_paths", side_effect=forbidden, create=True), \
                patch.object(validation, "configured_profile_digest", side_effect=forbidden, create=True), \
                patch.object(validation, "updater_snapshot", side_effect=forbidden, create=True), \
                patch.object(validation, "sha256", side_effect=forbidden):
            with patch.object(validation, "registry_snapshot", return_value={"startup": None}):
                self.assertEqual(validation.host_snapshot(), {"registry": {"startup": None}})
            with patch.object(validation, "registry_snapshot", side_effect=PermissionError("fixture registry denied")):
                with self.assertRaises(PermissionError):
                    validation.host_snapshot()

    @unittest.skipUnless(os.name == "nt", "Installer orchestration requires Windows APIs")
    def test_stale_standard_result_is_refused_before_installation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "standard-result.json").write_text(json.dumps({"status": "passed"}))
            state = {"format": 2, "payloadTreeSha256": "0" * 64, "payloadQualification": "bytes_only",
                     "root": str(root), "identity": "PlugAgenteHomologacao_0123456789ab",
                     "app": str(root / "app"), "data": str(root / "data"),
                     "control": str(root / "control"), "updaterData": str(root / "updater"),
                     "installer": str(root / "fixture-installer.exe")}
            with patch.object(validation.ctypes.windll.shell32, "IsUserAnAdmin", return_value=True), \
                 patch.object(validation, "verify_input_binding"), \
                 patch.object(validation, "registry_value", return_value=None), \
                 patch.object(validation, "host_snapshot", return_value={"registry": {}}), \
                 patch.object(validation, "run", side_effect=RuntimeError("installer dispatched")) as dispatch:
                with self.assertRaisesRegex(RuntimeError, "previous standard-user"):
                    validation.administrator_phase(state)
                dispatch.assert_not_called()
            self.assertFalse((root / "lifecycle-result.json").exists())

    @unittest.skipUnless(os.name == "nt", "Installer orchestration requires Windows APIs")
    def test_failed_install_keeps_failure_and_records_only_registration_preservation(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = {"format": 2, "payloadTreeSha256": "0" * 64, "payloadQualification": "bytes_only",
                     "root": str(root), "identity": "PlugAgenteHomologacao_0123456789ab",
                     "app": str(root / "app"), "data": str(root / "data"),
                     "control": str(root / "control"), "updaterData": str(root / "updater"),
                     "installer": str(root / "fixture-installer.exe")}
            with patch.object(validation.ctypes.windll.shell32, "IsUserAnAdmin", return_value=True), \
                    patch.object(validation, "verify_input_binding"), \
                    patch.object(validation, "registry_value", return_value=None), \
                    patch.object(validation, "host_snapshot", return_value={"registry": {}}), \
                    patch.object(validation, "run", side_effect=RuntimeError("synthetic install failure")):
                with self.assertRaisesRegex(RuntimeError, "synthetic install failure"):
                    validation.administrator_phase(state)
            result = json.loads((root / "lifecycle-result.json").read_text())
            self.assertEqual(result["status"], "failed")
            self.assertTrue(result["operationalRegistrationsPreserved"])
            self.assertNotIn("operationalInstallationPreserved", result)
            self.assertEqual(result["operationalStateInspection"], "registration_metadata_only")

    @unittest.skipUnless(os.name == "nt", "Installer orchestration requires Windows APIs")
    def test_changed_registration_is_recorded_as_a_failure(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = {"format": 2, "payloadTreeSha256": "0" * 64, "payloadQualification": "bytes_only",
                     "root": str(root), "identity": "PlugAgenteHomologacao_0123456789ab",
                     "app": str(root / "app"), "data": str(root / "data"),
                     "control": str(root / "control"), "updaterData": str(root / "updater"),
                     "installer": str(root / "fixture-installer.exe")}
            with patch.object(validation.ctypes.windll.shell32, "IsUserAnAdmin", return_value=True), \
                    patch.object(validation, "verify_input_binding"), \
                    patch.object(validation, "registry_value", return_value=None), \
                    patch.object(validation, "host_snapshot", side_effect=[{"registry": {}}, {"registry": {"startup": "changed"}}]), \
                    patch.object(validation, "run", side_effect=RuntimeError("synthetic install failure")):
                with self.assertRaisesRegex(RuntimeError, "registrations changed"):
                    validation.administrator_phase(state)
            result = json.loads((root / "lifecycle-result.json").read_text())
            self.assertEqual(result["status"], "failed")
            self.assertFalse(result["operationalRegistrationsPreserved"])


class LifecycleVerificationTests(unittest.TestCase):
    def test_failed_final_probe_cannot_leave_a_passed_report(self):
        result = {"status": "passed"}
        denied = PermissionError("fixture metadata denied")
        with patch.object(validation, "host_snapshot", side_effect=denied):
            with self.assertRaisesRegex(RuntimeError, "could not be verified") as raised:
                validation.verify_host_registration_preservation(result, {"registry": {}})
        self.assertIs(raised.exception.__cause__, denied)
        self.assertEqual(result["status"], "failed")
        self.assertIsNone(result["operationalRegistrationsPreserved"])

    def test_successful_probe_does_not_turn_a_failed_installation_into_success(self):
        for status in ("passed", "failed"):
            with self.subTest(status=status):
                result = {"status": status}
                with patch.object(validation, "host_snapshot", return_value={"registry": {}}):
                    validation.verify_host_registration_preservation(result, {"registry": {}})
                self.assertEqual(result["status"], status)
                self.assertTrue(result["operationalRegistrationsPreserved"])

    def test_changed_metadata_invalidates_a_previously_passed_report(self):
        result = {"status": "passed"}
        with patch.object(validation, "host_snapshot", return_value={"registry": {"startup": "changed"}}):
            with self.assertRaisesRegex(RuntimeError, "registrations changed"):
                validation.verify_host_registration_preservation(result, {"registry": {}})
        self.assertEqual(result["status"], "failed")
        self.assertFalse(result["operationalRegistrationsPreserved"])



class LifecycleInputBindingTests(unittest.TestCase):
    def test_reverified_inputs_do_not_promote_failed_phase(self):
        state = {"root": "private-root", "payloadTreeSha256": "0" * 64}
        for status in ("passed", "failed"):
            result = {"status": status}
            with patch.object(validation, "load_fixture", return_value=dict(state)):
                validation.verify_input_binding(state, result)
            self.assertEqual(result["status"], status)
            self.assertTrue(result["inputBindingVerified"])

    def test_changed_manifest_cannot_leave_a_passed_report(self):
        state = {"root": "private-root", "payloadTreeSha256": "0" * 64}
        result = {"status": "passed"}
        with patch.object(validation, "load_fixture", return_value={**state, "payloadTreeSha256": "1" * 64}):
            with self.assertRaisesRegex(RuntimeError, "binding changed"):
                validation.verify_input_binding(state, result)
        self.assertEqual(result["status"], "failed")
        self.assertFalse(result["inputBindingVerified"])

    def test_unreadable_inputs_fail_without_claiming_proven_mutation(self):
        state = {"root": "private-root"}
        result = {"status": "passed"}
        denied = PermissionError("private fixture denied")
        with patch.object(validation, "load_fixture", side_effect=denied):
            with self.assertRaisesRegex(RuntimeError, "could not be reverified") as error:
                validation.verify_input_binding(state, result)
        self.assertIs(error.exception.__cause__, denied)
        self.assertEqual(result["status"], "failed")
        self.assertFalse(result["inputBindingVerified"])



class LifecycleInspectionTests(unittest.TestCase):
    def test_inspection_whitelists_metadata_without_claiming_installed_or_built_source(self):
        state = {"format": 2, "identity": "PlugAgenteHomologacao_0123456789ab",
                 "payloadFiles": {"file": "0" * 64}, "payloadTreeSha256": "1" * 64,
                 "installerSha256": "2" * 64, "legacySourceCommit": "3" * 40,
                 "payloadQualification": "bytes_only", "privateKey": "must-not-be-output"}
        with patch.object(validation, "load_fixture", return_value=state):
            result = validation.inspect_fixture(Path("fixture.json"))
        self.assertEqual(result["scope"], "fixture-integrity-only")
        self.assertEqual(result["payloadFiles"], 1)
        self.assertFalse(result["installationPerformed"])
        self.assertFalse(result["buildSourceVerified"])
        self.assertEqual(result["installedState"], "not_checked")
        self.assertNotIn("installed", result)
        self.assertNotIn("must-not-be-output", json.dumps(result))

    @unittest.skipUnless(os.name == "nt", "Windows inspection CLI")
    def test_inspect_dispatch_does_not_enter_installation_or_request_elevation(self):
        from io import StringIO
        forbidden = AssertionError("inspection must not touch installed state")
        with patch.object(validation, "inspect_fixture", return_value={"scope": "fixture-integrity-only"}), \
                patch.object(validation, "administrator_phase", side_effect=forbidden), \
                patch.object(validation, "standard_user_phase", side_effect=forbidden), \
                patch.object(validation, "host_snapshot", side_effect=forbidden), \
                patch("sys.stdout", new_callable=StringIO) as output:
            validation.main(["--fixture", "fixture.json", "--phase", "inspect"])
        self.assertEqual(json.loads(output.getvalue())["scope"], "fixture-integrity-only")
        with self.assertRaisesRegex(SystemExit, "does not accept machine-change"):
            validation.main(["--fixture", "fixture.json", "--phase", "inspect", "--allow-machine-changes"])
