from pathlib import Path
import unittest

import yaml

from tool.ci.validate_ci_configuration import validate_configuration

ROOT = Path(__file__).resolve().parents[2]


def workflow(name):
    return yaml.safe_load((ROOT / ".github/workflows" / name).read_text(encoding="utf-8"))


class WorkflowRegressionTests(unittest.TestCase):
    def test_all_workflow_unittest_modules_are_available(self):
        self.assertEqual(validate_configuration(ROOT), [])

    def test_simulation_skips_every_publication_step(self):
        steps = workflow("release.yml")["jobs"]["publish"]["steps"]
        publication_steps = [step for step in steps if step["name"] in
                             {"Commit version bump", "Generate signed updater manifest", "Verify manifest and publish release"}]
        self.assertEqual(len(publication_steps), 3)
        for step in publication_steps:
            with self.subTest(step=step["name"]):
                self.assertEqual(step["if"], "${{ !inputs.dry_run }}")
        self.assertEqual(workflow("release.yml")["jobs"]["publish-appcast"]["if"], "${{ !inputs.dry_run }}")

    def test_native_contract_tests_fail_if_no_tests_are_registered(self):
        for name in ("release.yml", "flutter_ci.yml"):
            jobs = workflow(name)["jobs"]
            commands = [step["run"] for job in jobs.values() for step in job.get("steps", [])
                        if "ctest " in step.get("run", "")]
            self.assertTrue(commands, name)
            for command in commands:
                with self.subTest(workflow=name):
                    self.assertIn("--no-tests=error", command)
                    self.assertIn("--output-junit", command)

    def test_main_mutations_are_queued_in_the_same_group(self):
        for name, job in (("release.yml", "publish"), ("update-appcast.yml", "update-appcast")):
            with self.subTest(workflow=name):
                concurrency = workflow(name)["jobs"][job]["concurrency"]
                self.assertEqual(concurrency["group"], "plug-main-mutation")
                self.assertEqual(concurrency["queue"], "max")
                self.assertFalse(concurrency["cancel-in-progress"])

    def test_windows_debug_bundle_prepares_native_engine_once(self):
        steps = workflow("flutter_ci.yml")["jobs"]["windows-helper-smoke"]["steps"]
        preparations = [step for step in steps if "prepare_package_native.py --github-env" in step.get("run", "")]
        self.assertEqual(len(preparations), 1)

    def test_release_retries_preserve_rollout_and_validate_the_effective_percentage(self):
        caller = workflow("release.yml")["jobs"]["publish-appcast"]
        self.assertTrue(caller["with"]["preserve_existing_rollout"])
        job = workflow("update-appcast.yml")["jobs"]["update-appcast"]
        self.assertEqual(job["outputs"]["rollout_percentage"], "${{ steps.appcast.outputs.rollout_percentage }}")
        update = next(step for step in job["steps"] if step["name"] == "Update appcast.xml")
        self.assertIn("--preserve-existing-rollout", update["run"])
        self.assertEqual(update["env"]["PRESERVE_EXISTING_ROLLOUT"], "${{ inputs.preserve_existing_rollout }}")
        validate = next(step for step in job["steps"] if step["name"] == "Validate appcast.xml")
        self.assertIn('steps.appcast.outputs.rollout_percentage', validate["run"])

    def test_alerts_use_tested_logic_and_serialize_issue_updates(self):
        alert = workflow("scheduled-workflow-alert.yml")
        self.assertEqual(alert["concurrency"]["queue"], "max")
        self.assertFalse(alert["concurrency"]["cancel-in-progress"])
        script = alert["jobs"]["alert-on-consecutive-failures"]["steps"][-1]["with"]["script"]
        self.assertIn("./tool/ci/scheduled_workflow_alert.cjs", script)

    def test_python_shell_can_import_manifest_verification_from_the_workspace(self):
        steps = workflow("windows-installation-validation.yml")["jobs"]["installation"]["steps"]
        verification = next(step for step in steps if "from tool.updater.manifest import verify" in step.get("run", ""))
        self.assertEqual(verification["env"]["PYTHONPATH"], "${{ github.workspace }}")


if __name__ == "__main__":
    unittest.main()
