#!/usr/bin/env python3
from __future__ import annotations


import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]
_ROOT = _TOOL_DIR.parent
for _entry in (str(_ROOT), str(_TOOL_DIR)):
    if _entry not in sys.path:
        sys.path.insert(0, _entry)

import shutil
import subprocess

from py.script_utils import PROJECT_ROOT, Console, run

PACKAGE_DIR = PROJECT_ROOT / "tool" / "plug_agente_elevated_runner"
OUTPUT_DIR = PROJECT_ROOT / "build" / "elevated_runner"
OUTPUT_EXE = OUTPUT_DIR / "plug_agente_elevated_runner.exe"
CLI_BUILD_DIR = OUTPUT_DIR / "cli_out"


def _copy_native_sidecars(source_lib: Path, destination: Path) -> None:
    if not source_lib.is_dir():
        return
    destination.mkdir(parents=True, exist_ok=True)
    for asset in source_lib.iterdir():
        if asset.is_file():
            shutil.copy2(asset, destination / asset.name)


def _built_executable(bundle_bin: Path) -> Path:
    matches = sorted(bundle_bin.glob("plug_agente_elevated_runner*"))
    if not matches:
        raise FileNotFoundError(
            f"dart build cli did not produce plug_agente_elevated_runner in {bundle_bin}",
        )
    return matches[0]


def main() -> int:
    run(["dart", "pub", "get"], cwd=PACKAGE_DIR)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    if CLI_BUILD_DIR.exists():
        shutil.rmtree(CLI_BUILD_DIR)
    # sqlite3 3.x ships native libs via build hooks; `dart compile exe` cannot
    # run those hooks (`use 'dart build' instead`).
    run(
        [
            "dart",
            "build",
            "cli",
            "-t",
            "bin/plug_agente_elevated_runner.dart",
            "-o",
            str(CLI_BUILD_DIR),
        ],
        cwd=PACKAGE_DIR,
    )
    bundle = CLI_BUILD_DIR / "bundle"
    built = _built_executable(bundle / "bin")
    shutil.copy2(built, OUTPUT_EXE)
    _copy_native_sidecars(bundle / "lib", OUTPUT_DIR)
    print(f"Built elevated runner helper: {OUTPUT_EXE}")

    bundle_targets = [
        PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Release",
        PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Debug",
    ]
    for bundle_dir in bundle_targets:
        if bundle_dir.is_dir():
            shutil.copy2(OUTPUT_EXE, bundle_dir / "plug_agente_elevated_runner.exe")
            _copy_native_sidecars(bundle / "lib", bundle_dir)
            print(f"Copied helper to: {bundle_dir}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.SubprocessError:
        Console.fail("build_elevated_runner.py failed.")
        raise SystemExit(1)
