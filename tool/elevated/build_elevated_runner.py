#!/usr/bin/env python3
from __future__ import annotations


import sys
import argparse
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]
_ROOT = _TOOL_DIR.parent
for _entry in (str(_ROOT), str(_TOOL_DIR)):
    if _entry not in sys.path:
        sys.path.insert(0, _entry)

import shutil
import subprocess
import re

from py.script_utils import PROJECT_ROOT, Console, resolve_dart_sdk_executable, run
from tool.release.windows_version_info import application_version, set_version_info

PACKAGE_DIR = PROJECT_ROOT / "tool" / "plug_agente_elevated_runner"
OUTPUT_DIR = PROJECT_ROOT / "build" / "elevated_runner"
OUTPUT_EXE = OUTPUT_DIR / "plug_agente_elevated_runner.exe"
CLI_BUILD_DIR = OUTPUT_DIR / "cli_out"
FLAT_PACKAGE_DIR = OUTPUT_DIR / "flat_package"
FLAT_BUILD_DIR = OUTPUT_DIR / "flat_cli_out"


def _remove_private_build_directory(directory: Path) -> None:
    expected_root = PROJECT_ROOT.resolve() / 'build/elevated_runner'
    if OUTPUT_DIR.resolve() != expected_root or directory.resolve().parent != expected_root or directory.is_symlink():
        raise ValueError('Unexpected private helper build directory')
    if directory.exists():
        shutil.rmtree(directory)


def _built_executable(bundle_bin: Path) -> Path:
    matches = sorted(bundle_bin.glob("plug_agente_elevated_runner*"))
    if not matches:
        raise FileNotFoundError(
            f"dart build cli did not produce plug_agente_elevated_runner in {bundle_bin}",
        )
    return matches[0]


def _sqlite_sidecar_name(package: Path) -> str:
    contract = (package / 'lib/src/elevated_contract.dart').read_text(encoding='utf-8')
    match = re.search(r"sqliteSidecarFileName = '([a-z0-9_]+\.dll)'", contract)
    if match is None or match[1] == 'sqlite3.dll':
        raise ValueError('Missing elevated SQLite sidecar contract')
    return match[1]


def _install_flat_helper(executable: Path, sqlite: Path, destination: Path, sidecar_name: str) -> None:
    if sidecar_name == 'sqlite3.dll' or Path(sidecar_name).name != sidecar_name:
        raise ValueError('Elevated SQLite must use a dedicated sidecar filename')
    destination.mkdir(parents=True, exist_ok=True)
    shutil.copy2(executable, destination / 'plug_agente_elevated_runner.exe')
    shutil.copy2(sqlite, destination / sidecar_name)


def _prepare_flat_package(source: Path, destination: Path, runtime_package: Path, sidecar_name: str) -> None:
    destination.mkdir(parents=True, exist_ok=False)
    for name in ('lib', 'bin'):
        shutil.copytree(source / name, destination / name)
    shutil.copy2(source / 'pubspec.lock', destination / 'pubspec.lock')
    pubspec = (source / 'pubspec.yaml').read_text(encoding='utf-8')
    expected = 'path: ../../packages/windows_action_runtime'
    if expected not in pubspec or re.search(r'^hooks:', pubspec, re.M):
        raise ValueError('Unexpected helper package configuration')
    pubspec = pubspec.replace(expected, f'path: "{runtime_package.resolve().as_posix()}"')
    pubspec += ('\nhooks:\n  user_defines:\n    sqlite3:\n      source: system\n'
                f'      name_windows: {Path(sidecar_name).stem}\n')
    (destination / 'pubspec.yaml').write_text(pubspec, encoding='utf-8')


def main() -> int:
    parser = argparse.ArgumentParser(description='Build the elevated action runner.')
    parser.add_argument('--release-only', action='store_true', help='Copy only to the release bundle for installer packaging.')
    args = parser.parse_args()
    dart = resolve_dart_sdk_executable()
    run([dart, "pub", "get"], cwd=PACKAGE_DIR)
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    _remove_private_build_directory(CLI_BUILD_DIR)
    # sqlite3 3.x ships native libs via build hooks; `dart compile exe` cannot
    # run those hooks (`use 'dart build' instead`).
    run(
        [
            dart,
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
    sqlite = bundle / 'lib/sqlite3.dll'
    if not sqlite.is_file():
        raise FileNotFoundError('The pinned helper build did not produce sqlite3.dll')
    sidecar_name = _sqlite_sidecar_name(PACKAGE_DIR)
    # The standard CLI layout embeds ../lib paths. The Windows installer places
    # this helper beside the app instead, so compile a private package with a
    # dedicated library name. Keep the checksum-verified DLL from the first build.
    for directory in (FLAT_PACKAGE_DIR, FLAT_BUILD_DIR):
        _remove_private_build_directory(directory)
    _prepare_flat_package(PACKAGE_DIR, FLAT_PACKAGE_DIR,
                          PROJECT_ROOT / 'packages/windows_action_runtime', sidecar_name)
    run([dart, 'pub', 'get'], cwd=FLAT_PACKAGE_DIR)
    run([dart, 'build', 'cli', '-t', 'bin/plug_agente_elevated_runner.dart', '-o', str(FLAT_BUILD_DIR)],
        cwd=FLAT_PACKAGE_DIR)
    built = _built_executable(FLAT_BUILD_DIR / 'bundle/bin')
    _install_flat_helper(built, sqlite, OUTPUT_DIR, sidecar_name)
    set_version_info(OUTPUT_EXE, application_version())
    run([str(OUTPUT_EXE), "--help"])
    print(f"Built elevated runner helper: {OUTPUT_EXE}")

    bundle_targets = [PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Release"]
    if not args.release_only:
        bundle_targets.append(PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Debug")
    for bundle_dir in bundle_targets:
        if bundle_dir.is_dir():
            _install_flat_helper(OUTPUT_EXE, sqlite, bundle_dir, sidecar_name)
            print(f"Copied helper to: {bundle_dir}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except subprocess.SubprocessError:
        Console.fail("build_elevated_runner.py failed.")
        raise SystemExit(1)
