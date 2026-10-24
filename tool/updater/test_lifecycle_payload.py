from pathlib import Path
import os
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tool.updater import isolated_windows_fixture as fixtures
from tool.updater import lifecycle_payload as payloads


class LifecyclePayloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.project = Path(self.temporary.name) / "project"
        self.root = self.project / "build/homologation/windows-lifecycle-payload-test"
        for name in payloads.REQUIRED_PAYLOAD_FILES:
            path = self.root / "payload" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes(b"synthetic payload, never executed")
        owner = patch.object(fixtures, "PROJECT", self.project)
        owner.start()
        self.addCleanup(owner.stop)
        self.files = payloads.capture_payload(self.root)
        self.tree_hash = payloads.payload_tree_hash(self.files)

    def test_full_inventory_has_stable_order_independent_hash(self):
        reversed_files = dict(reversed(list(self.files.items())))
        self.assertEqual(payloads.payload_tree_hash(reversed_files), self.tree_hash)
        payloads.verify_payload(self.root, self.files, self.tree_hash)

    def test_modified_missing_and_added_files_are_refused(self):
        target = self.root / "payload/data/app.so"
        original = target.read_bytes()
        target.write_bytes(b"changed synthetic bytes")
        with self.assertRaisesRegex(RuntimeError, "payload changed"):
            payloads.verify_payload(self.root, self.files, self.tree_hash)
        target.unlink()
        with self.assertRaisesRegex(RuntimeError, "payload files are missing"):
            payloads.verify_payload(self.root, self.files, self.tree_hash)
        target.write_bytes(original)
        (self.root / "payload/unexpected.exe").write_bytes(b"unexpected synthetic bytes")
        with self.assertRaisesRegex(RuntimeError, "payload changed"):
            payloads.verify_payload(self.root, self.files, self.tree_hash)

    def test_invalid_or_external_inventory_names_are_refused_before_hashing_files(self):
        for name in ("../outside", "/outside", "C:/outside", "data/../outside", "data//app.so", "data/./app.so", "data\\app.so", "", "line\nname"):
            with self.subTest(name=name), patch.object(payloads, "sha256", side_effect=AssertionError("invalid inventory opened a file")):
                invalid = {**self.files, name: "0" * 64}
                with self.assertRaisesRegex(RuntimeError, "payload inventory entry"):
                    payloads.verify_payload(self.root, invalid, self.tree_hash)

    def test_missing_inventory_or_required_binary_and_invalid_digest_are_refused(self):
        invalid_cases = [None, {}, {"plug_agente.exe": "0" * 64}, {**self.files, "data/extra": "A" * 64}]
        for value in invalid_cases:
            with self.subTest(value=type(value).__name__), self.assertRaises(RuntimeError):
                payloads.verify_payload(self.root, value, self.tree_hash)
        with self.assertRaisesRegex(RuntimeError, "inventory hash"):
            payloads.verify_payload(self.root, self.files, "0" * 64)

    def test_file_budget_is_enforced_before_full_inventory_is_opened(self):
        with patch.object(payloads, "MAX_PAYLOAD_FILES", 2):
            with self.assertRaisesRegex(RuntimeError, "exceeds its limit"):
                payloads.capture_payload(self.root)

    def test_hard_link_is_refused_before_hashing_the_external_file(self):
        target = self.project / "outside.bin"
        target.write_bytes(b"must not be opened")
        linked = self.root / "payload/linked.bin"
        os.link(target, linked)
        original_hash = payloads.sha256
        def checked_hash(path):
            if path.samefile(target):
                self.fail("external hard-link content was opened")
            return original_hash(path)
        with patch.object(payloads, "sha256", side_effect=checked_hash):
            with self.assertRaisesRegex(RuntimeError, "Hard-linked"):
                payloads.capture_payload(self.root)

    @unittest.skipUnless(os.name == "nt", "Windows junction refusal")
    def test_junction_is_refused_before_reading_its_target(self):
        target = self.project / "outside"
        target.mkdir()
        (target / "private.bin").write_bytes(b"must not be opened")
        junction = self.root / "payload/linked"
        subprocess.run(["cmd", "/c", "mklink", "/J", str(junction), str(target)], capture_output=True, check=True)
        original_hash = payloads.sha256
        def checked_hash(path):
            if not path.resolve().is_relative_to(self.root / "payload"):
                self.fail("junction target was opened")
            return original_hash(path)
        try:
            with patch.object(payloads, "sha256", side_effect=checked_hash):
                with self.assertRaisesRegex(RuntimeError, "Linked lifecycle"):
                    payloads.capture_payload(self.root)
        finally:
            junction.rmdir()
