from __future__ import annotations

import json
import tempfile
import unittest
from pathlib import Path

try:
    from jsonschema import Draft7Validator  # type: ignore
except ImportError as error:  # pragma: no cover
    raise unittest.SkipTest(
        "jsonschema not installed; install with `pip install jsonschema`."
    ) from error


SCHEMA_PATH = (
    Path(__file__).resolve().parent.parent
    / "docs"
    / "communication"
    / "schemas"
    / "silent_update_launcher_status.schema.json"
)


class LauncherStatusSchemaTests(unittest.TestCase):
    def setUp(self) -> None:
        self.schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
        self.validator = Draft7Validator(self.schema)

    def test_empty_object_is_valid(self) -> None:
        # The helper may have written nothing yet (e.g., crashed before any
        # field landed); an empty object must still validate.
        errors = list(self.validator.iter_errors({}))
        self.assertEqual(errors, [])

    def test_full_realistic_payload_is_valid(self) -> None:
        payload = {
            "state": "completed",
            "strategy": "currentUserThenElevated",
            "installDirectory": "C:\\Program Files\\Plug Agente",
            "installerPath": "C:\\ProgramData\\Plug\\updates\\setup.exe",
            "logPath": "C:\\ProgramData\\Plug\\updates\\setup.log",
            "nonAdminExitCode": 0,
            "nonAdminDurationMs": 14523,
            "elevatedExitCode": None,
            "elevatedDurationMs": None,
            "elevatedRetryStarted": False,
            "waitForAppExitDurationMs": 234,
            "appPid": 12345,
            "signatureStatus": "valid",
            "signatureRequired": False,
            "actualSha256": "a" * 64,
            "hashValidationStatus": "valid",
            "installDirectoryWritable": True,
            "elevatedCancelled": False,
            "errorMessage": None,
            "lastUpdatedAt": "2026-05-26T12:34:56Z",
        }
        errors = list(self.validator.iter_errors(payload))
        self.assertEqual(errors, [])

    def test_invalid_state_enum_is_rejected(self) -> None:
        errors = list(self.validator.iter_errors({"state": "rebooting"}))
        self.assertTrue(errors, "expected schema to reject unknown state value")

    def test_invalid_sha256_length_is_rejected(self) -> None:
        errors = list(
            self.validator.iter_errors({"actualSha256": "too-short"})
        )
        self.assertTrue(errors)

    def test_negative_durations_are_rejected(self) -> None:
        errors = list(
            self.validator.iter_errors({"nonAdminDurationMs": -1})
        )
        self.assertTrue(errors)

    def test_validator_cli_accepts_valid_payload(self) -> None:
        # Bring the CLI module under test only when jsonschema is available.
        import sys

        sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
        from tool import validate_launcher_status  # type: ignore

        payload_dir = Path(tempfile.mkdtemp(prefix="launcher_status_"))
        payload = payload_dir / "status.json"
        payload.write_text(json.dumps({"state": "completed"}), encoding="utf-8")

        errors = validate_launcher_status.validate(payload)
        self.assertEqual(errors, [])


if __name__ == "__main__":
    unittest.main()
