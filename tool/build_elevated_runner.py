#!/usr/bin/env python3
from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

from py.script_utils import PROJECT_ROOT, Console, run

PACKAGE_DIR = PROJECT_ROOT / "tool" / "plug_agente_elevated_runner"
OUTPUT_DIR = PROJECT_ROOT / "build" / "elevated_runner"
OUTPUT_EXE = OUTPUT_DIR / "plug_agente_elevated_runner.exe"


def main() -> int:
    run(["dart", "pub", "get"], cwd=PACKAGE_DIR)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    run(
        [
            "dart",
            "compile",
            "exe",
            "bin/plug_agente_elevated_runner.dart",
            "-o",
            str(OUTPUT_EXE),
        ],
        cwd=PACKAGE_DIR,
    )
    print(f"Built elevated runner helper: {OUTPUT_EXE}")

    bundle_targets = [
        PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Release",
        PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Debug",
    ]
    for bundle_dir in bundle_targets:
        if bundle_dir.is_dir():
            shutil.copy2(OUTPUT_EXE, bundle_dir / "plug_agente_elevated_runner.exe")
            print(f"Copied helper to: {bundle_dir}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.SubprocessError:
        Console.fail("build_elevated_runner.py failed.")
        raise SystemExit(1)
