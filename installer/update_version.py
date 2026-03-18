#!/usr/bin/env python3
"""
Synchronize the pubspec.yaml version into installer/setup.iss.

Updates:
- installer/setup.iss: MyAppVersion

Run from project root:
  python installer/update_version.py
"""

import re
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = PROJECT_ROOT / "pubspec.yaml"
SETUP_ISS = PROJECT_ROOT / "installer" / "setup.iss"


def get_version_from_pubspec() -> str:
    content = PUBSPEC.read_text(encoding="utf-8")
    match = re.search(r'^version:\s*["\']?([\d.]+)', content, re.MULTILINE)
    if not match:
        raise SystemExit("Error: version not found in pubspec.yaml")
    return match.group(1).strip()


def update_setup_iss(version: str) -> None:
    content = SETUP_ISS.read_text(encoding="utf-8")
    new_content = re.sub(
        r'#define MyAppVersion\s+".*"',
        f'#define MyAppVersion "{version}"',
        content,
    )
    SETUP_ISS.write_text(new_content, encoding="utf-8")
    print(f"  setup.iss: MyAppVersion = {version}")


def main() -> None:
    version = get_version_from_pubspec()
    print(f"pubspec.yaml version: {version}")
    update_setup_iss(version)
    print("Synchronization completed.")


if __name__ == "__main__":
    main()
