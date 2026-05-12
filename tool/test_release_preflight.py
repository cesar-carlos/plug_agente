from __future__ import annotations

import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tool import release_preflight


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


if __name__ == "__main__":
    unittest.main()
