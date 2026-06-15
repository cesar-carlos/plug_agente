#!/usr/bin/env python3
from __future__ import annotations


import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]
_ROOT = _TOOL_DIR.parent
for _entry in (str(_ROOT), str(_TOOL_DIR)):
    if _entry not in sys.path:
        sys.path.insert(0, _entry)

import argparse
import json
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

PROJECT_ROOT = _ROOT
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


# Scan in chunks so we never load a >30 MB binary into memory just to find
# a 44-character base64 string.
_BINARY_SCAN_CHUNK_BYTES = 4 * 1024 * 1024


def _file_contains_bytes(path: Path, needle: bytes) -> bool:
    if not needle:
        return True
    with path.open("rb") as fh:
        overlap = b""
        while True:
            chunk = fh.read(_BINARY_SCAN_CHUNK_BYTES)
            if not chunk:
                return False
            haystack = overlap + chunk
            if needle in haystack:
                return True
            # Keep the trailing (len(needle) - 1) bytes so a match split across
            # two chunks is still detected.
            keep = max(0, len(needle) - 1)
            overlap = haystack[-keep:] if keep else b""


def ensure_feed_public_key_embedded(version: str, csv_keys: str) -> None:
    """Ensures every Ed25519 public key in [csv_keys] is present in the
    installer payload. Catches builds that forgot the
    `--dart-define=AUTO_UPDATE_FEED_PUBLIC_KEY=...` flag.

    Accepts a single key or a CSV (matches the runtime contract). A missing
    key would make every silent check report `feedSignatureStatus:
    publicKeyUnavailable`, defeating the rotation/signing rollout.
    """
    cleaned = (csv_keys or "").strip()
    if not cleaned:
        return
    installer = DIST_DIR / f"PlugAgente-Setup-{version}.exe"
    if not installer.exists():
        raise RuntimeError(
            f"Installer not found at {installer}; cannot verify embedded public key."
        )
    keys = [entry.strip() for entry in cleaned.split(",") if entry.strip()]
    missing: list[str] = []
    for key in keys:
        if not _file_contains_bytes(installer, key.encode("ascii")):
            missing.append(key)
    if missing:
        joined = ", ".join(f"{m[:8]}…" for m in missing)
        raise RuntimeError(
            f"Installer is missing AUTO_UPDATE_FEED_PUBLIC_KEY value(s) [{joined}]. "
            "Did the build forget the --dart-define flag? Re-run the build with the "
            "pubkey embedded; otherwise REQUIRE_FEED_SIGNATURE=true clients will "
            "report feedSignatureStatus=publicKeyUnavailable."
        )


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


def ensure_appcast_signing_tests_not_skipped() -> None:
    result = run(
        ["python", "-m", "unittest", "tool.appcast.test_appcast_signing", "-v"],
        check=False,
    )
    combined = f"{result.stdout}\n{result.stderr}"
    if result.returncode != 0:
        raise RuntimeError(
            "tool.appcast.test_appcast_signing failed. Install cryptography and re-run preflight."
            + (f"\n{combined.strip()}" if combined.strip() else "")
        )
    if "skipped=" in combined:
        raise RuntimeError(
            "tool.appcast.test_appcast_signing reported skipped tests "
            "(cryptography missing or suite disabled)."
        )


def ensure_early_tools(*, require_iscc: bool) -> None:
    """Toolchain for --early: tag/ISCC only; Flutter is installed later in CI."""
    missing = [command for command in ("git", "python") if not command_exists(command)]
    if require_iscc and find_iscc() is None:
        missing.append("ISCC")
    if missing:
        raise RuntimeError(f"Missing required command(s): {', '.join(missing)}")


def run_early_checks(args: argparse.Namespace, version_short: str) -> None:
    """Fast checks before bumping pubspec in CI (tag + toolchain only)."""
    ensure_early_tools(require_iscc=args.require_iscc)
    if not args.allow_existing_tag:
        ensure_tag_available(f"v{version_short}")


def run_optional_checks(args: argparse.Namespace) -> None:
    if args.analyze:
        run(["flutter", "analyze"])
    if args.tests:
        run(["flutter", "test"])
    if args.tests_ci:
        run(["flutter", "test", "--exclude-tags", "live || slow || perf"])
    if args.architecture:
        run(["flutter", "test", "test/architecture/layer_boundaries_test.dart"])
    if args.appcast_tooling:
        run(
            [
                "python",
                "-m",
                "unittest",
                "tool.appcast.test_appcast_manager",
                "tool.appcast.test_validate_release",
                "tool.appcast.test_appcast_signing",
                "-v",
            ]
        )
        ensure_appcast_signing_tests_not_skipped()


def list_github_actions_secrets(repo: str) -> set[str]:
    result = run(["gh", "secret", "list", "--repo", repo], check=False)
    if result.returncode != 0:
        return set()
    return {line.split()[0] for line in result.stdout.splitlines() if line.strip()}


def collect_publish_secret_warnings(repo: str) -> list[str]:
    secrets = list_github_actions_secrets(repo)
    warnings: list[str] = []
    if "RELEASE_PUBLISH_TOKEN" not in secrets:
        warnings.append(
            "RELEASE_PUBLISH_TOKEN is not configured: update-appcast.yml will not run "
            "automatically after publish (the publish workflow dispatches it as fallback)."
        )
    if "WINDOWS_CODE_SIGNING_CERT_BASE64" not in secrets:
        warnings.append(
            "WINDOWS_CODE_SIGNING_CERT_BASE64 is not configured: builds are unsigned and "
            "Authenticode verification is skipped in CI."
        )
    if "AUTO_UPDATE_FEED_PUBLIC_KEY" not in secrets:
        warnings.append(
            "AUTO_UPDATE_FEED_PUBLIC_KEY is not configured: feed signature embedding checks "
            "are skipped unless you pass --feed-public-key."
        )
    return warnings


def print_publish_workflow_hints(
    *,
    version_short: str,
    build_number: str,
    repo: str,
    skip_authenticode: bool,
) -> None:
    secrets = list_github_actions_secrets(repo)
    has_signing = "WINDOWS_CODE_SIGNING_CERT_BASE64" in secrets
    has_publish_token = "RELEASE_PUBLISH_TOKEN" in secrets

    print("\nPublish workflow hints:")
    print(f"  1. Optional dry run: gh workflow run \"Publish Windows Release\" --ref main")
    print(f"     -f version={version_short} -f build_number={build_number} -f dry_run=true")
    print("  2. Production publish:")
    authode_flag = "true" if skip_authenticode or not has_signing else "false"
    print(
        f"     gh workflow run \"Publish Windows Release\" --ref main "
        f"-f version={version_short} -f build_number={build_number} "
        f"-f run_tests=true -f require_signing=false -f dry_run=false "
        f"-f skip_authenticode_check={authode_flag}"
    )
    if not has_signing:
        print(
            "  WARN: WINDOWS_CODE_SIGNING_CERT_BASE64 is not configured; "
            "use skip_authenticode_check=true or the publish job will fail after the build."
        )
    if not has_publish_token:
        print(
            "  WARN: RELEASE_PUBLISH_TOKEN is not configured; "
            "update-appcast.yml will not run automatically after publish."
        )
        print(
            f"     After publish: gh workflow run \"Update Appcast on Release\" --ref main "
            f"-f release_tag=v{version_short} -f rollout_percentage=100 -f channel=stable"
        )
    else:
        print("  OK: RELEASE_PUBLISH_TOKEN is configured (appcast should auto-update).")


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
    parser.add_argument(
        "--tests-ci",
        action="store_true",
        help='Run flutter test with the same --exclude-tags filter used by Publish Windows Release.',
    )
    parser.add_argument(
        "--architecture",
        action="store_true",
        help="Run architecture/layer boundary tests.",
    )
    parser.add_argument(
        "--appcast-tooling",
        action="store_true",
        help="Run Python appcast/release validator unit tests (CI parity).",
    )
    parser.add_argument(
        "--gate",
        action="store_true",
        help="CI parity gate: --analyze --tests-ci --architecture --appcast-tooling.",
    )
    parser.add_argument(
        "--early",
        action="store_true",
        help="Fast CI check before version bump: --require-iscc, tag availability (--version required).",
    )
    parser.add_argument(
        "--build-number",
        default="1",
        help="Build suffix for publish workflow hints (default: 1).",
    )
    parser.add_argument(
        "--print-publish-hints",
        action="store_true",
        help="Print gh workflow commands and signing/appcast warnings after checks pass.",
    )
    parser.add_argument(
        "--check-secrets",
        action="store_true",
        help="Print GitHub Actions secret warnings (never fails; use with --gate or --print-publish-hints).",
    )
    parser.add_argument(
        "--feed-public-key",
        default="",
        help=(
            "Optional base64 (or CSV of base64) Ed25519 public key(s) that must "
            "appear inside the built installer. Use with --check-installer to "
            "catch builds that forgot the --dart-define for "
            "AUTO_UPDATE_FEED_PUBLIC_KEY."
        ),
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.gate:
        args.analyze = True
        args.tests_ci = True
        args.architecture = True
        args.appcast_tooling = True
    try:
        if args.check_secrets or args.print_publish_hints or args.early:
            for warning in collect_publish_secret_warnings(args.repo):
                print(f"WARN: {warning}", file=sys.stderr)

        if args.early:
            if not args.version:
                raise RuntimeError("--early requires --version (target short version).")
            run_early_checks(args, args.version)
            print(
                f"Early release preflight passed (target=v{args.version}, "
                f"tag_available={args.allow_existing_tag})."
            )
            return 0

        state = load_version_state()
        ensure_clean_worktree(allow_dirty=args.allow_dirty)
        ensure_version_sync(state, args.version)
        ensure_tools(require_iscc=args.require_iscc, check_pages=args.check_pages)
        if not args.allow_existing_tag:
            ensure_tag_available(f"v{state.short_version}")
        if args.check_installer:
            ensure_installer_exists(state.short_version)
            if args.feed_public_key:
                ensure_feed_public_key_embedded(state.short_version, args.feed_public_key)
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
    if args.print_publish_hints:
        expected = args.version or state.short_version
        secrets = list_github_actions_secrets(args.repo)
        has_signing = "WINDOWS_CODE_SIGNING_CERT_BASE64" in secrets
        print_publish_workflow_hints(
            version_short=expected,
            build_number=args.build_number.strip() or "1",
            repo=args.repo,
            skip_authenticode=not has_signing,
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())
