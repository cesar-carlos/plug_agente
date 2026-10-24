import json
import os
from pathlib import Path
import tempfile
import subprocess
import unittest
from unittest.mock import patch

from tool.updater import isolated_windows_fixture as fixtures
from tool.updater import lifecycle_handoff as handoffs


class LifecycleHandoffTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        project = Path(self.temporary.name) / "project"
        self.root = project / "build/homologation/windows-lifecycle-handoff"
        self.root.mkdir(parents=True)
        self.state = {"root": str(self.root), "identity": "PlugAgenteHomologacao_0123456789ab",
                      "installerSha256": "a" * 64, "payloadTreeSha256": "b" * 64}
        (self.root / "fixture.json").write_text(json.dumps(self.state))
        owner = patch.object(fixtures, "PROJECT", project)
        owner.start()
        self.addCleanup(owner.stop)

    def valid_result(self, handoff):
        return {**handoffs.result_binding(handoff), "status": "passed", "elevated": False,
                "checks": sorted(handoffs.CHECKS)}

    def save_result(self, result):
        (self.root / handoffs.RESULT).write_text(json.dumps(result))

    def test_absent_handoff_cannot_claim_or_publish_phase(self):
        with self.assertRaises(FileNotFoundError):
            handoffs.claim_handoff(self.state)
        self.assertFalse((self.root / handoffs.CLAIM).exists())
        self.assertFalse((self.root / handoffs.RESULT).exists())

    def test_claim_is_unique_and_complete_result_is_bound_to_current_attempt(self):
        handoff = handoffs.create_handoff(self.state)
        self.assertEqual(handoffs.claim_handoff(self.state), handoff)
        with self.assertRaises(FileExistsError):
            handoffs.claim_handoff(self.state)
        self.save_result(self.valid_result(handoff))
        handoffs.verify_result(self.state, handoff)
        with self.assertRaisesRegex(RuntimeError, "result already exists"):
            handoffs.claim_handoff(self.state)

    def test_stale_files_block_preparation_without_changing_evidence(self):
        for name in (handoffs.READY, handoffs.CLAIM, handoffs.RESULT, handoffs.RESULT + ".tmp"):
            path = self.root / name
            path.write_bytes(b"previous evidence")
            with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, "previous standard-user"):
                handoffs.create_handoff(self.state)
            self.assertEqual(path.read_bytes(), b"previous evidence")
            path.unlink()

    def test_changed_manifest_or_payload_cannot_claim_prepared_handoff(self):
        handoffs.create_handoff(self.state)
        for state in ({**self.state, "payloadTreeSha256": "c" * 64}, {**self.state, "identity": "other"}):
            with self.subTest(state=state["identity"]), self.assertRaisesRegex(RuntimeError, "does not match"):
                handoffs.claim_handoff(state)
        (self.root / "fixture.json").write_text("changed manifest")
        with self.assertRaisesRegex(RuntimeError, "does not match"):
            handoffs.claim_handoff(self.state)
        self.assertFalse((self.root / handoffs.CLAIM).exists())

    def test_incomplete_duplicate_elevated_and_other_attempt_results_are_refused(self):
        handoff = handoffs.create_handoff(self.state)
        handoffs.claim_handoff(self.state)
        original = self.valid_result(handoff)
        cases = [{"status": "passed"}, {**original, "phaseId": "0" * 64},
                 {**original, "fixtureBinding": "0" * 64}, {**original, "elevated": True},
                 {**original, "elevated": 0}, {**original, "checks": []},
                 {**original, "checks": [original["checks"][0]] * len(handoffs.CHECKS)},
                 {**original, "checks": [1] * len(handoffs.CHECKS)}]
        for result in cases:
            self.save_result(result)
            with self.subTest(keys=list(result)), self.assertRaisesRegex(RuntimeError, "incomplete or belongs"):
                handoffs.verify_result(self.state, handoff)

    def test_changed_claim_or_fixture_invalidates_completed_result(self):
        handoff = handoffs.create_handoff(self.state)
        handoffs.claim_handoff(self.state)
        self.save_result(self.valid_result(handoff))
        (self.root / handoffs.CLAIM).write_text(json.dumps({**handoff, "phaseId": "0" * 64}))
        with self.assertRaisesRegex(RuntimeError, "binding changed"):
            handoffs.verify_result(self.state, handoff)

    @unittest.skipUnless(os.name == "nt", "Windows non-overwriting rename contract")
    def test_result_is_published_complete_and_cannot_be_overwritten(self):
        handoff = handoffs.create_handoff(self.state)
        handoffs.claim_handoff(self.state)
        result = self.valid_result(handoff)
        original_dump = json.dump
        def checked_dump(value, output, **kwargs):
            self.assertFalse((self.root / handoffs.RESULT).exists())
            original_dump(value, output, **kwargs)
            self.assertFalse((self.root / handoffs.RESULT).exists())
        with patch.object(handoffs.json, "dump", side_effect=checked_dump):
            handoffs.write_result(self.state, result)
        handoffs.verify_result(self.state, handoff)
        self.assertFalse((self.root / (handoffs.RESULT + ".tmp")).exists())
        before = (self.root / handoffs.RESULT).read_bytes()
        with self.assertRaisesRegex(RuntimeError, "never overwrite"):
            handoffs.write_result(self.state, {"status": "failed"})
        self.assertEqual((self.root / handoffs.RESULT).read_bytes(), before)

    def test_finished_administrator_phase_cannot_claim_still_unconsumed_handoff(self):
        handoffs.create_handoff(self.state)
        (self.root / "lifecycle-result.json").write_text(json.dumps({"status": "failed"}))
        with self.assertRaisesRegex(RuntimeError, "Administrator phase already ended"):
            handoffs.claim_handoff(self.state)
        self.assertFalse((self.root / handoffs.CLAIM).exists())

    @unittest.skipUnless(os.name == "nt", "Windows dangling junction metadata")
    def test_dangling_phase_junction_is_refused_before_installation(self):
        target = self.root / "removed-target"
        target.mkdir()
        junction = self.root / handoffs.READY
        subprocess.run(["cmd", "/c", "mklink", "/J", str(junction), str(target)],
                       capture_output=True, check=True)
        target.rmdir()
        try:
            self.assertFalse(junction.exists())
            with self.assertRaisesRegex(RuntimeError, "previous standard-user"):
                handoffs.assert_fresh(self.state)
        finally:
            junction.rmdir()
