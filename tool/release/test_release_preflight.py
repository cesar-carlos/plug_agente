from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tool.release import release_preflight


class ReleasePreflightTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temp_dir = tempfile.TemporaryDirectory()
        self.root = Path(self.temp_dir.name)
        self.pubspec = self.root / "pubspec.yaml"
        self.setup_iss = self.root / "installer" / "setup.iss"
        self.app_version = self.root / "lib" / "core" / "constants" / "app_version.g.dart"
        self.dist_dir = self.root / "installer" / "dist"
        self.setup_iss.parent.mkdir(parents=True)
        self.app_version.parent.mkdir(parents=True)
        self.dist_dir.mkdir(parents=True)
        self.write_version_files()

        patches = [
            patch.object(release_preflight, "PROJECT_ROOT", self.root),
            patch.object(release_preflight, "PUBSPEC", self.pubspec),
            patch.object(release_preflight, "SETUP_ISS", self.setup_iss),
            patch.object(release_preflight, "APP_VERSION_DART", self.app_version),
            patch.object(release_preflight, "DIST_DIR", self.dist_dir),
        ]
        self.patchers = patches
        for patcher in patches:
            patcher.start()

    def tearDown(self) -> None:
        for patcher in reversed(self.patchers):
            patcher.stop()
        self.temp_dir.cleanup()

    def write_version_files(
        self,
        *,
        full_version: str = "1.6.6+1",
        setup_version: str = "1.6.6",
        generated_version: str = "1.6.6+1",
    ) -> None:
        self.pubspec.write_text(f"name: plug_agente\nversion: {full_version}\n", encoding="utf-8")
        self.setup_iss.write_text(f'#define MyAppVersion "{setup_version}"\n', encoding="utf-8")
        self.app_version.write_text(f'const String appVersion = "{generated_version}";\n', encoding="utf-8")

    def test_load_version_state_reads_synced_files(self) -> None:
        state = release_preflight.load_version_state()

        self.assertEqual(state.full_version, "1.6.6+1")
        self.assertEqual(state.short_version, "1.6.6")
        self.assertEqual(state.setup_version, "1.6.6")
        self.assertEqual(state.generated_version, "1.6.6+1")

    def test_ensure_version_sync_rejects_setup_mismatch(self) -> None:
        self.write_version_files(setup_version="1.6.5")
        state = release_preflight.load_version_state()

        with self.assertRaisesRegex(RuntimeError, "setup.iss version"):
            release_preflight.ensure_version_sync(state, "1.6.6")

    def test_ensure_clean_worktree_rejects_dirty_status(self) -> None:
        def fake_run(_: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
            return subprocess.CompletedProcess(args=[], returncode=0, stdout=" M pubspec.yaml\n", stderr="")

        with patch.object(release_preflight, "run", side_effect=fake_run):
            with self.assertRaisesRegex(RuntimeError, "Working tree is not clean"):
                release_preflight.ensure_clean_worktree(allow_dirty=False)

    def test_ensure_tag_available_rejects_existing_remote_tag(self) -> None:
        def fake_run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
            stdout = ""
            if cmd[:3] == ["git", "ls-remote", "--tags"]:
                stdout = "abc123\trefs/tags/v1.6.6\n"
            return subprocess.CompletedProcess(args=cmd, returncode=0, stdout=stdout, stderr="")

        with patch.object(release_preflight, "run", side_effect=fake_run):
            with self.assertRaisesRegex(RuntimeError, "Remote tag already exists"):
                release_preflight.ensure_tag_available("v1.6.6")

    def test_ensure_installer_exists_accepts_non_empty_asset(self) -> None:
        installer = self.dist_dir / "PlugAgente-Setup-1.6.6.exe"
        installer.write_bytes(b"installer")

        release_preflight.ensure_installer_exists("1.6.6")

    def test_ensure_feed_public_key_embedded_no_op_when_empty(self) -> None:
        # No key configured -> nothing to check, must return cleanly.
        release_preflight.ensure_feed_public_key_embedded("1.6.6", "")
        release_preflight.ensure_feed_public_key_embedded("1.6.6", "   ")

    def test_ensure_feed_public_key_embedded_accepts_when_present(self) -> None:
        installer = self.dist_dir / "PlugAgente-Setup-1.6.6.exe"
        # Synthetic installer payload that embeds the pubkey verbatim, as it
        # would after --dart-define injection at compile time.
        installer.write_bytes(b"prefix-AgioCsHZr/MmqPmckUOzs5IKWwjkCRaEFgQGS3wwRNA=-suffix")

        release_preflight.ensure_feed_public_key_embedded(
            "1.6.6",
            "AgioCsHZr/MmqPmckUOzs5IKWwjkCRaEFgQGS3wwRNA=",
        )

    def test_ensure_feed_public_key_embedded_rejects_when_missing(self) -> None:
        installer = self.dist_dir / "PlugAgente-Setup-1.6.6.exe"
        installer.write_bytes(b"installer without any key embedded")

        with self.assertRaisesRegex(RuntimeError, "missing AUTO_UPDATE_FEED_PUBLIC_KEY"):
            release_preflight.ensure_feed_public_key_embedded(
                "1.6.6",
                "AgioCsHZr/MmqPmckUOzs5IKWwjkCRaEFgQGS3wwRNA=",
            )

    def test_ensure_feed_public_key_embedded_accepts_csv_when_all_present(self) -> None:
        installer = self.dist_dir / "PlugAgente-Setup-1.6.6.exe"
        installer.write_bytes(
            b"prefix-keyOne-middle-keyTwo-suffix"
        )

        release_preflight.ensure_feed_public_key_embedded("1.6.6", "keyOne, keyTwo")

    def test_ensure_feed_public_key_embedded_rejects_csv_when_one_missing(self) -> None:
        installer = self.dist_dir / "PlugAgente-Setup-1.6.6.exe"
        installer.write_bytes(b"prefix-keyOne-suffix")

        with self.assertRaisesRegex(RuntimeError, "missing AUTO_UPDATE_FEED_PUBLIC_KEY"):
            release_preflight.ensure_feed_public_key_embedded("1.6.6", "keyOne,keyTwo")

    def test_ensure_feed_public_key_embedded_handles_match_across_chunks(self) -> None:
        installer = self.dist_dir / "PlugAgente-Setup-1.6.6.exe"
        chunk = release_preflight._BINARY_SCAN_CHUNK_BYTES
        key = "boundaryKey"
        # Split the key across the chunk boundary so the implementation must
        # carry over (key_len - 1) bytes to detect it.
        payload = b"a" * (chunk - 3) + key.encode("ascii") + b"b" * 1024
        installer.write_bytes(payload)

        release_preflight.ensure_feed_public_key_embedded("1.6.6", key)

    def test_run_wraps_cmd_and_bat_files_for_windows_execution(self) -> None:
        with (
            patch.object(release_preflight.shutil, "which", return_value=r"C:\tools\flutter.bat"),
            patch.object(release_preflight.subprocess, "run") as subprocess_run,
        ):
            subprocess_run.return_value = subprocess.CompletedProcess(
                args=[],
                returncode=0,
                stdout="",
                stderr="",
            )

            release_preflight.run(["flutter", "analyze"])

        called_cmd = subprocess_run.call_args.args[0]
        called_kwargs = subprocess_run.call_args.kwargs
        self.assertEqual(
            called_cmd,
            ["cmd.exe", "/d", "/c", r"C:\tools\flutter.bat", "analyze"],
        )
        self.assertEqual(called_kwargs["encoding"], "utf-8")
        self.assertEqual(called_kwargs["errors"], "replace")

    def test_ensure_github_pages_workflow_ready_accepts_actions_pages(self) -> None:
        result = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout='{"build_type":"workflow"}',
            stderr="",
        )

        with patch.object(release_preflight, "run", return_value=result):
            release_preflight.ensure_github_pages_workflow_ready("owner/repo")

    def test_main_with_gate_invokes_ci_parity_checks(self) -> None:
        state = release_preflight.VersionState(
            full_version="1.6.6+1",
            short_version="1.6.6",
            setup_version="1.6.6",
            generated_version="1.6.6+1",
        )
        with (
            patch.object(release_preflight, "load_version_state", return_value=state),
            patch.object(release_preflight, "ensure_clean_worktree"),
            patch.object(release_preflight, "ensure_version_sync"),
            patch.object(release_preflight, "ensure_tools"),
            patch.object(release_preflight, "ensure_tag_available"),
            patch.object(release_preflight, "run_optional_checks") as optional_checks,
        ):
            code = release_preflight.main(
                ["--gate", "--version", "1.6.6", "--allow-dirty", "--allow-existing-tag"]
            )

        self.assertEqual(code, 0)
        args = optional_checks.call_args.args[0]
        self.assertTrue(args.analyze)
        self.assertTrue(args.tests_ci)
        self.assertTrue(args.architecture)
        self.assertTrue(args.appcast_tooling)

    def test_ensure_appcast_signing_tests_not_skipped_rejects_skipped_suite(self) -> None:
        result = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout="OK (skipped=1)",
            stderr="",
        )
        with patch.object(release_preflight, "run", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "skipped tests"):
                release_preflight.ensure_appcast_signing_tests_not_skipped()

    def test_early_checks_validates_tag_without_version_sync(self) -> None:
        with (
            patch.object(release_preflight, "ensure_tools"),
            patch.object(release_preflight, "ensure_tag_available") as tag_check,
        ):
            release_preflight.run_early_checks(
                release_preflight.build_parser().parse_args(
                    ["--early", "--version", "1.6.7", "--require-iscc"]
                ),
                "1.6.7",
            )
        tag_check.assert_called_once_with("v1.6.7")

    def test_collect_publish_secret_warnings_lists_missing_secrets(self) -> None:
        with patch.object(release_preflight, "list_github_actions_secrets", return_value=set()):
            warnings = release_preflight.collect_publish_secret_warnings("owner/repo")
        self.assertGreaterEqual(len(warnings), 2)
        joined = " ".join(warnings)
        self.assertIn("RELEASE_PUBLISH_TOKEN", joined)
        self.assertIn("WINDOWS_CODE_SIGNING_CERT_BASE64", joined)

    def test_list_github_actions_secrets_parses_names(self) -> None:
        result = subprocess.CompletedProcess(
            args=[],
            returncode=0,
            stdout="RELEASE_PUBLISH_TOKEN\t2026-01-01\nWINDOWS_CODE_SIGNING_CERT_BASE64\t2026-01-01\n",
            stderr="",
        )
        with patch.object(release_preflight, "run", return_value=result):
            names = release_preflight.list_github_actions_secrets("owner/repo")
        self.assertEqual(
            names,
            {"RELEASE_PUBLISH_TOKEN", "WINDOWS_CODE_SIGNING_CERT_BASE64"},
        )

    def test_ensure_github_pages_workflow_ready_rejects_missing_pages(self) -> None:
        result = subprocess.CompletedProcess(
            args=[],
            returncode=1,
            stdout="",
            stderr="Not Found",
        )

        with patch.object(release_preflight, "run", return_value=result):
            with self.assertRaisesRegex(RuntimeError, "GitHub Pages is not enabled"):
                release_preflight.ensure_github_pages_workflow_ready("owner/repo")


if __name__ == "__main__":
    unittest.main()
