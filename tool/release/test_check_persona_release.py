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
