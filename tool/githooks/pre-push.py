#!/usr/bin/env python3
from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
RELEASE_SENSITIVE_PATTERN = re.compile(
    r"^(pubspec\.yaml|lib/|test/|tool/release_preflight\.py|tool/pre_publish_release\.py)"
)


def main() -> int:
    if os.environ.get("SKIP_RELEASE_GATE") == "1":
        return 0

    branch = subprocess.run(
        ["git", "rev-parse", "--abbrev-ref", "HEAD"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    ).stdout.strip()
    if branch != "main":
        return 0

    stdin = sys.stdin.read().strip()
    if stdin:
        first_line = stdin.splitlines()[0].strip()
        parts = first_line.split()
        if len(parts) >= 3:
            remote_ref = parts[2]
            if remote_ref and not remote_ref.endswith("refs/heads/main"):
                return 0

    changed = subprocess.run(
        ["git", "diff", "--name-only", "origin/main...HEAD"],
        cwd=PROJECT_ROOT,
        capture_output=True,
        text=True,
        check=False,
    ).stdout.splitlines()
    if not changed:
        changed = subprocess.run(
            ["git", "diff", "--name-only", "--cached"],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            check=False,
        ).stdout.splitlines()

    if not any(RELEASE_SENSITIVE_PATTERN.match(path.strip()) for path in changed if path.strip()):
        return 0

    print("pre-push: running release gate (--gate) for release-sensitive changes on main...")
    result = subprocess.run(
        [
            sys.executable,
            "tool/release_preflight.py",
            "--gate",
            "--allow-dirty",
            "--allow-existing-tag",
            "--check-secrets",
        ],
        cwd=PROJECT_ROOT,
        check=False,
    )
    if result.returncode != 0:
        print("pre-push: release gate failed. Fix issues or push with SKIP_RELEASE_GATE=1.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
