from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from tool.py.script_utils import (
    canonical_windows_executable,
    resolve_command,
    resolve_dart_sdk_executable,
)


class CanonicalWindowsExecutableTests(unittest.TestCase):
    def test_rewrites_pathext_uppercase_exe_suffix(self) -> None:
        rewritten = canonical_windows_executable(
            r"C:\hostedtoolcache\windows\flutter\bin\cache\dart-sdk\bin\dart.EXE",
        )

        self.assertTrue(rewritten.endswith("dart.exe"))
        self.assertFalse(rewritten.endswith(".EXE"))
        self.assertNotIn("EXE.exe", rewritten)

    def test_leaves_lowercase_exe_and_non_exe_paths_unchanged(self) -> None:
        exe_path = r"C:\flutter\bin\cache\dart-sdk\bin\dart.exe"
        bat_path = r"C:\flutter\bin\dart.bat"

        self.assertEqual(canonical_windows_executable(exe_path), exe_path)
        self.assertEqual(canonical_windows_executable(bat_path), bat_path)


class ResolveCommandTests(unittest.TestCase):
    def test_canonicalizes_windows_exe_resolved_by_which(self) -> None:
        with patch(
            "tool.py.script_utils.shutil.which",
            return_value=r"C:\sdk\bin\dart.EXE",
        ):
            command = resolve_command(["dart", "build", "cli"])

        self.assertEqual(command[0], r"C:\sdk\bin\dart.exe")
        self.assertEqual(command[1:], ["build", "cli"])


class ResolveDartSdkExecutableTests(unittest.TestCase):
    def test_prefers_flutter_sdk_dart_exe_with_lowercase_suffix(self) -> None:
        with tempfile.TemporaryDirectory() as raw_dir:
            flutter_root = Path(raw_dir)
            flutter_bat = flutter_root / "bin" / "flutter.bat"
            sdk_dart = flutter_root / "bin" / "cache" / "dart-sdk" / "bin" / "dart.exe"
            sdk_dart.parent.mkdir(parents=True)
            flutter_bat.write_text("", encoding="utf-8")
            sdk_dart.write_text("", encoding="utf-8")

            with patch(
                "tool.py.script_utils.shutil.which",
                side_effect=lambda name: str(flutter_bat) if name == "flutter" else None,
            ):
                resolved = resolve_dart_sdk_executable()

        self.assertEqual(Path(resolved), sdk_dart.resolve())
        self.assertTrue(resolved.endswith("dart.exe"))

    def test_canonicalizes_pathext_dart_when_flutter_is_unavailable(self) -> None:
        with patch(
            "tool.py.script_utils.shutil.which",
            side_effect=lambda name: (
                None if name == "flutter" else r"C:\sdk\bin\dart.EXE"
            ),
        ):
            resolved = resolve_dart_sdk_executable()

        self.assertEqual(resolved, r"C:\sdk\bin\dart.exe")
