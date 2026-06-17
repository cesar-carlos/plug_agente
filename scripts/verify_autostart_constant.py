#!/usr/bin/env python3
from __future__ import annotations

import re
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
CANONICAL_PATH = PROJECT_ROOT / "constants" / "autostart_arg.txt"
LAUNCH_ARGS_CONSTANTS_PATH = PROJECT_ROOT / "lib" / "core" / "constants" / "launch_args_constants.dart"
HEADER_PATH = PROJECT_ROOT / "windows" / "runner" / "launch_args_constants.h"
CONSTANTS_ISS_PATH = PROJECT_ROOT / "installer" / "constants.iss"


def main() -> int:
    canonical = CANONICAL_PATH.read_text(encoding="utf-8").strip()
    if not canonical:
        print("constants/autostart_arg.txt is empty", file=sys.stderr)
        return 1

    failed = False

    launch_args_constants = LAUNCH_ARGS_CONSTANTS_PATH.read_text(encoding="utf-8")
    if f"autostartArg = '{canonical}'" not in launch_args_constants:
        print(
            f"MISMATCH: launch_args_constants.dart does not contain autostartArg = '{canonical}'"
        )
        failed = True

    header = HEADER_PATH.read_text(encoding="utf-8")
    if f'kAutostartArg[] = "{canonical}"' not in header:
        print(f'MISMATCH: launch_args_constants.h does not contain kAutostartArg = "{canonical}"')
        failed = True

    constants_iss = CONSTANTS_ISS_PATH.read_text(encoding="utf-8")
    match = re.search(r'#define\s+AutostartArg\s+"([^"]+)"', constants_iss)
    if not match:
        print("MISMATCH: installer/constants.iss does not define AutostartArg")
        failed = True
    elif match.group(1) != canonical:
        print(
            "MISMATCH: installer/constants.iss AutostartArg is "
            f"'{match.group(1)}', expected '{canonical}'"
        )
        failed = True

    if failed:
        print(f"Run this script from repo root. Canonical value: {canonical}")
        return 1

    print(f"OK: All files use autostart constant: {canonical}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
