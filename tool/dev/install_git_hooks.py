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
