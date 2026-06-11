#!/usr/bin/env python3
from __future__ import annotations

import argparse

from py.script_utils import Console, PROJECT_ROOT, run


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Install optional repository git hooks (pre-push release gate).",
    )
    parser.parse_args()

    hooks_path = PROJECT_ROOT / "tool" / "githooks"
    run(["git", "config", "core.hooksPath", "tool/githooks"], cwd=PROJECT_ROOT)
    Console._emit(Console.GREEN, f"Installed git hooks from {hooks_path}")
    print("Pre-push runs release_preflight --gate when pushing main with pubspec/lib/test changes.")
    print("Skip once: set SKIP_RELEASE_GATE=1")
    print("Uninstall: git config --unset core.hooksPath")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
