import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from tool.updater import isolated_windows_fixture as fixtures
from tool.updater import validate_isolated_windows_lifecycle as validation
from tool.updater.validate_windows_installation import sha256


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
        self.state = {"format": 1, "root": str(self.root), "identity": self.identity,
                      "productionActivationGate": False,
                      "appName": "Plug Agente Homologacao 0123456789ab",
                      "protocol": self.identity.lower().replace("_", "-"),
                      "installer": str(self.installer), "installerSha256": sha256(self.installer)}
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
        for field, value in (("format", 2), ("format", True), ("format", 1.0), ("productionActivationGate", True), ("productionActivationGate", None)):
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
