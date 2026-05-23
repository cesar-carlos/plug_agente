#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = PROJECT_ROOT / "pubspec.yaml"
SETUP_ISS = PROJECT_ROOT / "installer" / "setup.iss"
APP_VERSION_DART = PROJECT_ROOT / "lib" / "core" / "constants" / "app_version.g.dart"
DIST_DIR = PROJECT_ROOT / "installer" / "dist"

ISCC_PATHS = [
    "ISCC",
    r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    r"C:\Program Files\Inno Setup 6\ISCC.exe",
]


@dataclass(frozen=True)
class VersionState:
    full_version: str
    short_version: str
    setup_version: str
    generated_version: str


def resolve_command(cmd: Sequence[str]) -> list[str]:
    args = list(cmd)
    if not args:
        raise RuntimeError("Command cannot be empty.")

    executable = args[0]
    resolved = shutil.which(executable) or executable
    if Path(resolved).suffix.lower() in {".bat", ".cmd"}:
        return ["cmd.exe", "/d", "/c", resolved, *args[1:]]
    return [resolved, *args[1:]]


def run(cmd: Sequence[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        resolve_command(cmd),
        cwd=PROJECT_ROOT,
        check=check,
        text=True,
        encoding="utf-8",
        errors="replace",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def parse_required(pattern: str, content: str, label: str) -> str:
    match = re.search(pattern, content, re.MULTILINE)
    if not match:
        raise ValueError(f"Unable to parse {label}.")
    return match.group(1).strip()


def load_version_state() -> VersionState:
    full_version = parse_required(
        r'^version:\s*["\']?(\d+\.\d+\.\d+(?:\+\d+)?)["\']?\s*(?:#|$)',
        PUBSPEC.read_text(encoding="utf-8"),
        "pubspec.yaml version",
    )
    setup_version = parse_required(
        r'^#define MyAppVersion\s+"([^"]+)"',
        SETUP_ISS.read_text(encoding="utf-8-sig"),
        "installer/setup.iss MyAppVersion",
    )
    generated_version = parse_required(
        r'^const String appVersion = "([^"]+)";',
        APP_VERSION_DART.read_text(encoding="utf-8"),
        "app_version.g.dart appVersion",
    )
    return VersionState(
        full_version=full_version,
        short_version=full_version.split("+", 1)[0],
        setup_version=setup_version,
        generated_version=generated_version,
    )


def ensure_clean_worktree(*, allow_dirty: bool) -> None:
    if allow_dirty:
        return
    status = run(["git", "status", "--porcelain"]).stdout.strip()
    if status:
        raise RuntimeError("Working tree is not clean. Commit or stash changes, or pass --allow-dirty.")


def ensure_version_sync(state: VersionState, expected_version: str | None) -> None:
    if expected_version and state.short_version != expected_version:
        raise RuntimeError(
            f"pubspec short version {state.short_version!r} does not match expected version {expected_version!r}."
        )
    if state.setup_version != state.short_version:
        raise RuntimeError(
            f"installer/setup.iss version {state.setup_version!r} does not match pubspec {state.short_version!r}."
        )
    if state.generated_version != state.full_version:
        raise RuntimeError(
            f"app_version.g.dart version {state.generated_version!r} does not match pubspec {state.full_version!r}."
        )


def command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def find_iscc() -> str | None:
    for path in ISCC_PATHS:
        if path == "ISCC" and command_exists("ISCC"):
            return "ISCC"
        if path != "ISCC" and Path(path).exists():
            return path
    return None


def ensure_tools(*, require_iscc: bool, check_pages: bool) -> None:
    missing = [command for command in ("git", "python", "flutter") if not command_exists(command)]
    if check_pages and not command_exists("gh"):
        missing.append("gh")
    if require_iscc and find_iscc() is None:
        missing.append("ISCC")
    if missing:
        raise RuntimeError(f"Missing required command(s): {', '.join(missing)}")


def ensure_tag_available(tag: str) -> None:
    local = run(["git", "tag", "--list", tag]).stdout.strip()
    if local:
        raise RuntimeError(f"Local tag already exists: {tag}")
    remote = run(["git", "ls-remote", "--tags", "origin", tag]).stdout.strip()
    if remote:
        raise RuntimeError(f"Remote tag already exists: {tag}")


def ensure_installer_exists(version: str) -> None:
    installer = DIST_DIR / f"PlugAgente-Setup-{version}.exe"
    if not installer.exists():
        raise RuntimeError(f"Installer not found: {installer}")
    if installer.stat().st_size <= 0:
        raise RuntimeError(f"Installer is empty: {installer}")


def ensure_github_pages_workflow_ready(repo: str) -> None:
    result = run(["gh", "api", f"repos/{repo}/pages"], check=False)
    if result.returncode != 0:
        details = (result.stderr or result.stdout or "").strip()
        raise RuntimeError(
            "GitHub Pages is not enabled for this repository. "
            "Enable Pages with GitHub Actions as the build source before publishing."
            + (f" Details: {details}" if details else "")
        )

    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("Unable to parse GitHub Pages API response.") from error

    build_type = str(payload.get("build_type") or "")
    if build_type != "workflow":
        raise RuntimeError(
            "GitHub Pages must use GitHub Actions as the build source "
            f"(expected build_type='workflow', actual={build_type!r})."
        )


def run_optional_checks(args: argparse.Namespace) -> None:
    if args.analyze:
        run(["flutter", "analyze"])
    if args.tests:
        run(["flutter", "test"])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate local readiness for a Plug Agente release.")
    parser.add_argument("--version", help="Expected short version, for example 1.6.6.")
    parser.add_argument("--allow-dirty", action="store_true", help="Allow local uncommitted changes.")
    parser.add_argument("--allow-existing-tag", action="store_true", help="Do not fail when the release tag exists.")
    parser.add_argument("--require-iscc", action="store_true", help="Require Inno Setup compiler to be available.")
    parser.add_argument("--check-installer", action="store_true", help="Require installer/dist asset for this version.")
    parser.add_argument("--check-pages", action="store_true", help="Require GitHub Pages to be enabled for Actions deploy.")
    parser.add_argument("--repo", default="cesar-carlos/plug_agente", help="GitHub repository used by --check-pages.")
    parser.add_argument("--analyze", action="store_true", help="Run flutter analyze.")
    parser.add_argument("--tests", action="store_true", help="Run flutter test.")
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        state = load_version_state()
        ensure_clean_worktree(allow_dirty=args.allow_dirty)
        ensure_version_sync(state, args.version)
        ensure_tools(require_iscc=args.require_iscc, check_pages=args.check_pages)
        if not args.allow_existing_tag:
            ensure_tag_available(f"v{state.short_version}")
        if args.check_installer:
            ensure_installer_exists(state.short_version)
        if args.check_pages:
            ensure_github_pages_workflow_ready(args.repo)
        run_optional_checks(args)
    except Exception as error:
        print(f"Release preflight failed: {error}", file=sys.stderr)
        return 1

    print(
        "Release preflight passed "
        f"(version={state.full_version}, tag=v{state.short_version}, setup={state.setup_version})."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
