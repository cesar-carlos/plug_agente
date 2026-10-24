import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tool.updater import isolated_windows_fixture as fixtures
from tool.updater import validate_isolated_windows_lifecycle as validation
from tool.updater.validate_windows_installation import sha256
from tool.updater.lifecycle_payload import REQUIRED_PAYLOAD_FILES, payload_tree_hash


class IsolatedLifecyclePathTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name) / "project"
        self.root = self.project / "build/homologation/windows-lifecycle-private-test"
        self.root.mkdir(parents=True)
        self.identity = "PlugAgenteHomologacao_0123456789ab"
        self.installer = self.root / "package/fixture.exe"
        self.installer.parent.mkdir()
        self.installer.write_bytes(b"private installer placeholder, never executed")
        payload = self.root / "payload"
        for name in REQUIRED_PAYLOAD_FILES:
            path = payload / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"private fixture placeholder, never executed")
        payload_files = {name: sha256(payload / name) for name in REQUIRED_PAYLOAD_FILES}
        self.state = {"format": 2, "payloadFiles": payload_files,
                      "payloadTreeSha256": payload_tree_hash(payload_files), "payloadQualification": "bytes_only", "root": str(self.root), "identity": self.identity,
                      "productionActivationGate": False,
                      "appName": "Plug Agente Homologacao 0123456789ab",
                      "protocol": self.identity.lower().replace("_", "-"),
                      "installer": str(self.installer), "installerSha256": sha256(self.installer)}
        legacy = self.root / "legacy/native/Release/plug_update_service.exe"
        legacy.parent.mkdir(parents=True)
        legacy.write_bytes(b"private historical placeholder, never executed")
        self.state.update({"legacyService": str(legacy), "legacyServiceSha256": sha256(legacy), "legacySourceCommit": "a" * 40})
        self.manifest = self.root / "fixture.json"
        self.save()
        owner = patch.object(fixtures, "PROJECT", self.project)
        owner.start()
        self.addCleanup(owner.stop)
        proof = patch.object(validation, "assert_isolated_sources")
        proof.start()
        self.addCleanup(proof.stop)
        environment = patch.dict(os.environ, {"ProgramFiles": str(self.project / "program-files"),
                                             "ProgramData": str(self.project / "program-data")})
        environment.start()
        self.addCleanup(environment.stop)

    def save(self):
        self.manifest.write_text(json.dumps(self.state), encoding="utf-8")

    def test_outside_manifest_is_refused_before_any_content_read(self):
        external = self.project / "fixture.json"
        external.write_text("private outside content", encoding="utf-8")
        with patch.object(Path, "read_text", side_effect=AssertionError("outside file was opened")):
            with self.assertRaisesRegex(RuntimeError, "owned workspace"):
                validation.load_fixture(external)

    def test_owned_manifest_loads_but_existing_fixture_cannot_be_rebuilt(self):
        result = validation.load_fixture(self.manifest)
        self.assertEqual(result["identity"], self.identity)
        with self.assertRaisesRegex(RuntimeError, "existing lifecycle"):
            fixtures.require_fixture_root(self.root, fresh=True)

    def test_builder_refuses_external_roots_and_allows_only_new_owned_children(self):
        with self.assertRaisesRegex(RuntimeError, "owned workspace"):
            fixtures.require_fixture_root(self.project / "external", fresh=True)
        candidate = self.root.parent / "windows-lifecycle-new-private"
        self.assertEqual(fixtures.require_fixture_root(candidate, fresh=True), candidate)
        self.assertFalse(candidate.exists())

    def test_artifact_outside_fixture_is_refused_before_hashing(self):
        outside = self.project / "outside.exe"
        outside.write_bytes(b"outside")
        self.state["installer"] = str(outside)
        self.save()
        with patch.object(validation, "sha256", side_effect=AssertionError("outside file was hashed")):
            with self.assertRaisesRegex(RuntimeError, "outside its owned"):
                validation.load_fixture(self.manifest)

    def test_format_and_activation_gate_are_required_and_hash_mismatch_is_refused(self):
        for field, value in (("format", 3), ("format", True), ("format", 2.0), ("productionActivationGate", True), ("productionActivationGate", None)):
            with self.subTest(field=field, value=value):
                old = self.state[field]
                self.state[field] = value
                self.save()
                with self.assertRaisesRegex(RuntimeError, "format, activation"):
                    validation.load_fixture(self.manifest)
                self.state[field] = old
        self.save()
        self.installer.write_bytes(b"modified fixture bytes")
        with self.assertRaisesRegex(RuntimeError, "installer binding"):
            validation.load_fixture(self.manifest)

    def test_missing_historical_binding_is_refused_before_phase_dispatch(self):
        self.state.pop("legacyService")
        self.save()
        with self.assertRaisesRegex(RuntimeError, "Historical supervisor binding is required"):
            validation.load_fixture(self.manifest)

    def test_modified_payload_is_refused_before_lifecycle_execution(self):
        (self.root / "payload/updater/plug_update_service.exe").write_bytes(b"modified private payload")
        with self.assertRaisesRegex(RuntimeError, "payload changed"):
            validation.load_fixture(self.manifest)

    def test_historical_unbound_payload_is_refused_without_rewriting_its_manifest(self):
        self.state["format"] = 1
        self.state.pop("payloadFiles")
        self.save()
        before = self.manifest.read_bytes()
        with self.assertRaisesRegex(RuntimeError, "format, activation"):
            validation.load_fixture(self.manifest)
        self.assertEqual(self.manifest.read_bytes(), before)

    def test_oversize_manifest_is_refused_before_json_read(self):
        self.manifest.write_bytes(b" " * (256 * 1024 + 1))
        with patch.object(Path, "read_text", side_effect=AssertionError("large file was read")):
            with self.assertRaisesRegex(RuntimeError, "size limit"):
                validation.load_fixture(self.manifest)

    @unittest.skipUnless(os.name == "nt", "Windows junction regression")
    def test_junction_fixture_root_is_refused_before_manifest_read(self):
        import subprocess
        linked = self.root.parent / "windows-lifecycle-linked"
        subprocess.run(["cmd", "/c", "mklink", "/J", str(linked), str(self.root)],
                       capture_output=True, check=True)
        try:
            with patch.object(Path, "read_text", side_effect=AssertionError("linked file was opened")):
                with self.assertRaisesRegex(RuntimeError, "Linked lifecycle"):
                    validation.load_fixture(linked / "fixture.json")
        finally:
            linked.rmdir()
