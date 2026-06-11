#!/usr/bin/env python3
"""Migrate legacy benchmark_logs/*/summary.json files into benchmarks/history/."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from tool.py.benchmark_common import HISTORY_DIR, LEGACY_LOGS_DIR, ensure_on_path
from tool.py.benchmark_migrate import migrate_legacy_file


def discover_legacy_summaries(source_dir: Path) -> list[Path]:
    if not source_dir.is_dir():
        return []
    return sorted(source_dir.glob("*/summary.json"))


def main(argv: list[str] | None = None) -> int:
    ensure_on_path()
    parser = argparse.ArgumentParser(description="Migrate legacy benchmark_logs to schema v1 history.")
    parser.add_argument(
        "--source-dir",
        type=Path,
        default=LEGACY_LOGS_DIR,
        help="Legacy benchmark_logs root (default: benchmark_logs/)",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=HISTORY_DIR,
        help="Destination history root (default: benchmarks/history/)",
    )
    parser.add_argument("--dry-run", action="store_true", help="List sources without writing files.")
    args = parser.parse_args(argv)

    sources = discover_legacy_summaries(args.source_dir)
    if not sources:
        print(f"No legacy summary.json files found under {args.source_dir}")
        return 0

    print(f"Found {len(sources)} legacy summary file(s).")
    for source in sources:
        if args.dry_run:
            print(f"  would migrate: {source}")
            continue
        destination = migrate_legacy_file(source, args.output_dir)
        payload = json.loads(destination.read_text(encoding="utf-8"))
        suite_count = len(payload.get("suites", []))
        print(f"  migrated: {source.name} -> {destination} ({suite_count} suites)")

    if args.dry_run:
        print("Dry-run complete; no files written.")
    else:
        print(f"Migration complete under {args.output_dir}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
