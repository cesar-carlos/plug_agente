import copy
import json
from pathlib import Path
import tempfile
import unittest

from tool.benchmarks.action_ui_resources import PHASES, compare, summarize


def fixture():
    rows = [{"metadata": {"format": 1, "os": "Windows", "processors": 4,
        "machineId": "fixture", "sdkRevision": "sdk", "mode": "profile",
        "phaseSeconds": 30, "scenario": "silent-wait-v1", "appVersion": "test"}}]
    for index, phase in enumerate(PHASES):
        for tick in range(7):
            elapsed = index * 35000 + tick * 5000
            rows.append({"phase": phase, "elapsedMs": elapsed, "processors": 4,
                "cpuMicros": elapsed * 100, "frames": index, "rssBytes": 100 * 1048576,
                "commitBytes": 80 * 1048576, "providerNotifications": index,
                "running": 1 if phase.startswith("running-") else 0,
                "actionJobs": [{"pid": 42, "cpuMicros": elapsed}],
                "renderingEnabled": phase != "running-tray"})
    return [*rows, {"completed": True}]


class ActionUiResourcesTest(unittest.TestCase):
    def summarize_rows(self, rows):
        with tempfile.TemporaryDirectory() as directory:
            samples = Path(directory) / "samples.jsonl"
            samples.write_text("\n".join(json.dumps(row) for row in rows), encoding="utf-8")
            return summarize(samples)

    def test_normalized_cpu_and_memory_slope(self):
        result = self.summarize_rows(fixture())
        for phase in PHASES:
            self.assertEqual(result["phases"][phase]["cpuPercentMachine"], 2.5)
            self.assertEqual(result["phases"][phase]["rssGrowthMiBPerMinute"], 0)
        self.assertFalse(compare(result, result)["regressions"])

    def test_rejects_incomplete_failed_or_early_stopped_action(self):
        cases = [fixture()[:-1], [*fixture()[:-1], {"error": "render failed"}, {"completed": True}]]
        stopped = fixture()
        stopped[10]["running"] = 0
        cases.append(stopped)
        reset = fixture()
        reset[6]["cpuMicros"] = 0
        cases.append(reset)
        for rows in cases:
            with self.subTest(rows=rows[-1]), self.assertRaises(ValueError):
                self.summarize_rows(rows)

    def test_detects_regression_without_overwriting_baseline(self):
        baseline = self.summarize_rows(fixture())
        original = copy.deepcopy(baseline)
        current = copy.deepcopy(baseline)
        current["phases"]["running-tray"]["framesPerSecond"] = 60
        current["phases"]["running-visible"]["rssPeakMiB"] = 8000
        result = compare(current, baseline)
        self.assertIn("running-tray.framesPerSecond", result["regressions"])
        self.assertIn("running-visible.rssPeakMiB", result["regressions"])
        self.assertEqual(baseline, original)

    def test_rejects_different_machine_or_duration(self):
        baseline = self.summarize_rows(fixture())
        for key, value in (("machineId", "other"), ("phaseSeconds", 900), ("mode", "debug")):
            changed = copy.deepcopy(baseline)
            changed["metadata"][key] = value
            with self.assertRaises(ValueError):
                compare(changed, baseline)

    def test_rejects_claimed_long_run_with_short_samples(self):
        rows = fixture()
        rows[0]["metadata"]["phaseSeconds"] = 450
        with self.assertRaisesRegex(ValueError, "Shortened phase"):
            self.summarize_rows(rows)

    def test_memory_growth_gate_requires_five_minutes_of_stable_samples(self):
        baseline = self.summarize_rows(fixture())
        current = copy.deepcopy(baseline)
        current["phases"]["running-visible"]["rssGrowthMiBPerMinute"] = 100
        self.assertNotIn("running-visible.rssGrowthMiBPerMinute", compare(current, baseline)["regressions"])
        for report in (current, baseline):
            report["phases"]["running-visible"]["seconds"] = 300
        self.assertIn("running-visible.rssGrowthMiBPerMinute", compare(current, baseline)["regressions"])

    def test_focus_changes_make_phase_comparison_inconclusive(self):
        baseline = self.summarize_rows(fixture())
        rows = fixture()
        rows[12]["lifecycle"] = "inactive"
        current = self.summarize_rows(rows)
        self.assertIn("running-visible", compare(current, baseline)["inconclusivePhases"])


if __name__ == "__main__":
    unittest.main()
