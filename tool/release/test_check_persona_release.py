import unittest
from tool.release.check_persona_release import REQUIRED, ready

class PersonaReleaseGateTest(unittest.TestCase):
    def test_partial_manifest_never_publishes(self):
        self.assertFalse(ready({"generation":"persona-v2","ready":False,"requiredGates":REQUIRED,"completedGates":REQUIRED}))
        self.assertFalse(ready({"generation":"persona-v2","ready":True,"requiredGates":REQUIRED,"completedGates":[]}))
    def test_empty_or_replaced_gates_do_not_bypass_acceptance(self):
        self.assertFalse(ready({"generation":"persona-v2","ready":True,"requiredGates":[],"completedGates":[]}))
    def test_complete_manifest_is_required(self):
        self.assertTrue(ready({"generation":"persona-v2","ready":True,"requiredGates":REQUIRED,"completedGates":REQUIRED}))

    def test_shared_knowledge_is_required_even_when_other_gates_are_complete(self):
        self.assertIn("shared-knowledge-and-compatibility", REQUIRED)
        previous = [gate for gate in REQUIRED if gate != "shared-knowledge-and-compatibility"]
        self.assertFalse(ready({"generation": "persona-v2", "ready": True,
                                "requiredGates": previous, "completedGates": previous}))
        self.assertFalse(ready({"generation": "persona-v2", "ready": True,
                                "requiredGates": REQUIRED, "completedGates": previous}))

    def test_every_required_gate_is_independent_of_the_manifest_claim(self):
        for missing in REQUIRED:
            with self.subTest(gate=missing):
                partial = [gate for gate in REQUIRED if gate != missing]
                self.assertFalse(ready({"generation": "persona-v2", "ready": True,
                                        "requiredGates": partial, "completedGates": partial}))
