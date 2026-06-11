#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys

from py.script_utils import Console, PROJECT_ROOT, run


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Local gate before triggering Publish Windows Release on GitHub Actions.",
    )
    parser.add_argument("--version", required=True, help="Release version (e.g. 1.8.4)")
    parser.add_argument("--build-number", default="1", help="Build number suffix")
    parser.add_argument(
        "--allow-dirty",
        action="store_true",
        help="Allow dirty working tree in release preflight",
    )
    parser.add_argument(
        "--skip-gate",
        action="store_true",
        help="Skip analyze/tests gate checks",
    )
    args = parser.parse_args()

    if not args.skip_gate:
        Console._emit(Console.CYAN, "Running publish gate (analyze + CI tests + architecture + appcast tooling)...")
        preflight_args = [
            "python",
            "tool/release_preflight.py",
            "--version",
            args.version,
            "--gate",
            "--check-secrets",
            "--print-publish-hints",
            "--build-number",
            args.build_number,
        ]
        if args.allow_dirty:
            preflight_args.append("--allow-dirty")
        result = run(preflight_args, check=False)
        if result.returncode != 0:
            raise RuntimeError(f"Release preflight failed with exit code {result.returncode}.")
    else:
        print("WARNING: Skipped --gate checks (--skip-gate).")

    print()
    Console._emit(Console.GREEN, "Next steps:")
    print("  A) Validate installer build without publishing: use dry_run=true in Publish Windows Release.")
    print("  B) Or run Release Preflight workflow in Actions for a full Windows build on CI.")
    print("  C) When ready, use the gh command printed above for production publish.")
    print("  D) Optional: python tool/install_git_hooks.py (pre-push gate on main for lib/test changes).")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
