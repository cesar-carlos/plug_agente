#!/usr/bin/env python3
"""Validates a silent-update launcher status JSON against the canonical schema.

Used by the CI preflight to confirm the helper smoke test emits a payload
that the Dart coordinator can still parse. Catches divergence between the
helper's C++ code and the cross-component contract documented in
`docs/communication/schemas/silent_update_launcher_status.schema.json`.

Usage:

    python tool/validate_launcher_status.py path/to/status.json

Dependency:

    pip install jsonschema>=4.0.0
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

try:
    from jsonschema import Draft7Validator
except ImportError as error:  # pragma: no cover - import-time guard
    print(
        "jsonschema is required. Install with `pip install jsonschema`.",
        file=sys.stderr,
    )
    raise SystemExit(2) from error


SCHEMA_PATH = (
    Path(__file__).resolve().parent.parent
    / "docs"
    / "communication"
    / "schemas"
    / "silent_update_launcher_status.schema.json"
)


def validate(payload_path: Path) -> list[str]:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    payload = json.loads(payload_path.read_text(encoding="utf-8"))
    validator = Draft7Validator(schema)
    return [
        f"{'/'.join(str(p) for p in error.absolute_path) or '<root>'}: {error.message}"
        for error in validator.iter_errors(payload)
    ]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("payload", type=Path, help="Path to the launcher status JSON file.")
    args = parser.parse_args()

    if not args.payload.exists():
        print(f"Payload not found: {args.payload}", file=sys.stderr)
        return 2

    errors = validate(args.payload)
    if errors:
        print(f"Launcher status payload at {args.payload} failed schema validation:")
        for entry in errors:
            print(f"  - {entry}")
        return 1
    print(f"Launcher status payload at {args.payload} matches the schema.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
