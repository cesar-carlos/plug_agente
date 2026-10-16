import ctypes
from contextlib import closing
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tool.updater import validate_existing_windows_installation as validation


class ProfileDigestTests(unittest.TestCase):
    def test_updater_mutations_in_installer_log_are_not_accepted_as_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            log = Path(temporary) / "repair.log"
            for command in ("--enroll", "--revoke", "--prepare-control", "--prepare-host-upgrade"):
                log.write_text(f"plug_update_client.exe {command} argument: Exit code: 0", encoding="utf-8")
                with self.assertRaisesRegex(RuntimeError, "Unrequested updater mutation"):
                    validation.verify_no_updater_mutations(log)
            log.write_text("--check-install 0: Exit code: 0\n--core: Exit code: 0", encoding="utf-8")
            validation.verify_no_updater_mutations(log)

    @unittest.skipUnless(os.name == "nt", "Snapshot ACLs require Windows")
    def test_protected_backup_remains_readable_after_reprotecting_existing_files(self):
        with tempfile.TemporaryDirectory() as temporary:
            evidence = Path(temporary) / "evidence"
            evidence.mkdir()
            validation.protect_backup(evidence)
            nested = evidence / "backup"
            nested.mkdir()
            content = nested / "profile.dat"
            content.write_bytes(b"private-profile")
            validation.protect_backup(evidence)
            self.assertEqual(content.read_bytes(), b"private-profile")
            content.write_bytes(b"updated-private-profile")
            self.assertEqual(content.read_bytes(), b"updated-private-profile")

    def test_digest_is_stable_when_rows_are_reordered_and_contains_no_secrets(self):
        with tempfile.TemporaryDirectory() as temporary:
            database = Path(temporary) / "profile.db"
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute("CREATE TABLE configs (id INTEGER, secret BLOB)")
                connection.executemany("INSERT INTO configs VALUES (?, ?)", [(1, b"secret-one"), (2, b"secret-two")])
                connection.execute("CREATE TABLE executions (value TEXT)")
                connection.execute("INSERT INTO executions VALUES ('volatile')")
            original = validation.configured_profile_digest(database)
            self.assertNotIn("secret", json.dumps(original))
            self.assertNotIn("executions", original)
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute("DELETE FROM configs")
                connection.executemany("INSERT INTO configs VALUES (?, ?)", [(2, b"secret-two"), (1, b"secret-one")])
            self.assertEqual(validation.configured_profile_digest(database), original)
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute("UPDATE configs SET secret=? WHERE id=1", (b"changed",))
            self.assertNotEqual(validation.configured_profile_digest(database), original)

    def test_unknown_profile_schema_is_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            database = Path(temporary) / "profile.db"
            with closing(sqlite3.connect(database)) as connection, connection:
                connection.execute("CREATE TABLE unrelated (id INTEGER)")
            with self.assertRaisesRegex(RuntimeError, "No configured-profile"):
                validation.configured_profile_digest(database)


@unittest.skipUnless(os.name == "nt", "Existing host repair uses Windows handles")
class ExistingRepairTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.app = self.root / "app"
        self.app.mkdir()
        (self.app / "plug_agente.exe").write_bytes(b"core")
        (self.app / "plug_install_check.exe").write_bytes(b"probe")
        (self.app / "install-mode.ini").write_text("[installation]\nworkerVersion=1.8.7+1\n")
        self.data = self.root / "data"
        self.data.mkdir()
        with closing(sqlite3.connect(self.data / "agent_config.db")) as connection, connection:
            connection.execute("CREATE TABLE configs (id INTEGER)")
            connection.execute("INSERT INTO configs VALUES (1)")
        (self.data / "settings.json").write_text("{}")
        self.vault = self.root / "vault.dat"
        self.vault.write_bytes(b"encrypted-vault")
        self.installer = self.root / "installer.exe"
        self.installer.write_bytes(b"installer")
        self.evidence = self.root / "evidence"
        for target, value in (("installation_paths", (self.app, self.data, self.vault)),
                              ("registry_snapshot", {"startup": "preserved"}), ("updater_snapshot", {"policy": "preserved"})):
            mocked = patch.object(validation, target, return_value=value)
            mocked.start()
            self.addCleanup(mocked.stop)
        with patch.object(validation, "protect_backup"):
            validation.prepare(self.installer, self.evidence)
        (self.evidence / "repair.log").write_text("--check-install 0: Exit code: 0", encoding="utf-8")

    def test_changed_profile_refuses_repair_before_any_installer_execution(self):
        with closing(sqlite3.connect(self.data / "agent_config.db")) as connection, connection:
            connection.execute("INSERT INTO configs VALUES (2)")
        with patch.object(ctypes.windll.shell32, "IsUserAnAdmin", return_value=True), patch.object(validation.subprocess, "run") as run:
            with self.assertRaisesRegex(RuntimeError, "Profile changed"):
                validation.validate_repair(self.evidence)
            run.assert_not_called()
        self.assertEqual(json.loads((self.evidence / "result.json").read_text())["status"], "failed")

    def test_changed_updater_refuses_repair_before_any_installer_execution(self):
        with patch.object(ctypes.windll.shell32, "IsUserAnAdmin", return_value=True), \
                patch.object(validation, "updater_snapshot", return_value={"policy": "changed"}), \
                patch.object(validation.subprocess, "run") as run:
            with self.assertRaisesRegex(RuntimeError, "integration changed"):
                validation.validate_repair(self.evidence)
            run.assert_not_called()

    def test_missing_elevation_is_recorded_without_running_installer(self):
        with patch.object(ctypes.windll.shell32, "IsUserAnAdmin", return_value=False), \
                patch.object(validation.subprocess, "run") as run:
            with self.assertRaisesRegex(RuntimeError, "requires Windows elevation"):
                validation.validate_repair(self.evidence)
            run.assert_not_called()
        self.assertEqual(json.loads((self.evidence / "result.json").read_text())["status"], "failed")

    def test_repair_preserves_profile_and_never_requests_upgrade_or_uninstall(self):
        with patch.object(ctypes.windll.shell32, "IsUserAnAdmin", return_value=True), \
                patch.object(validation, "lock_core_against_replacement", return_value=42), \
                patch.object(ctypes.windll.kernel32, "CloseHandle"), \
                patch.object(validation.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, b"", b"")) as run:
            result = validation.validate_repair(self.evidence)
        self.assertEqual(result["status"], "passed")
        command = run.call_args_list[0].args[0]
        self.assertIn("/REPAIR=optional", command)
        self.assertIn("/NOCLOSEAPPLICATIONS", command)
        self.assertIn("/AUTOUPDATE=0", command)
        self.assertFalse(any("UPGRADE" in value or "unins" in value for value in command))
        self.assertEqual(len(run.call_args_list), 4)

    def test_failed_installer_cannot_be_reported_as_passed(self):
        with patch.object(ctypes.windll.shell32, "IsUserAnAdmin", return_value=True), \
                patch.object(validation, "lock_core_against_replacement", return_value=42), \
                patch.object(ctypes.windll.kernel32, "CloseHandle"), \
                patch.object(validation.subprocess, "run", return_value=subprocess.CompletedProcess([], 1, b"", b"")):
            with self.assertRaisesRegex(RuntimeError, "Optional repair failed"):
                validation.validate_repair(self.evidence)
        self.assertEqual(json.loads((self.evidence / "result.json").read_text())["status"], "failed")
