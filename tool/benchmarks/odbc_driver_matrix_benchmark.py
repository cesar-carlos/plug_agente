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
import os
import subprocess
import sys
from pathlib import Path

from py.script_utils import (
    PROJECT_ROOT,
    TOOL_DIR,
    get_effective_env_value,
    import_dotenv_if_present,
    resolve_env_path,
    run_streaming,
)


BENCHMARKS_DIR = TOOL_DIR / "benchmarks"


def invoke_benchmark(script_name: str, output_directory: Path | None) -> int:
    script_path = BENCHMARKS_DIR / script_name
    command = [sys.executable, str(script_path)]
    if output_directory is None:
        return subprocess.run(command, cwd=PROJECT_ROOT, check=False).returncode
    return run_streaming(command, cwd=PROJECT_ROOT)


def run_benchmark_for_driver(
    *,
    driver_name: str,
    driver_slug: str,
    dsn: str,
    output_directory: Path | None,
) -> None:
    if not dsn:
        print(f"Skipping {driver_name}: DSN not configured")
        return

    print()
    print(f"==> {driver_name}")
    print(f"Native/adaptive pool eligible: {driver_name != 'SQL Anywhere'}")

    from tool.py.benchmark_common import resolve_dart_odbc_fast_root, write_json
    from tool.py.odbc_benchmark_runner import run_odbc_async_benchmark, run_odbc_streaming_benchmark

    package_root = resolve_dart_odbc_fast_root()
    if package_root is None:
        raise RuntimeError("Locked odbc_fast package not found")
    environment = os.environ.copy()
    environment["ODBC_TEST_DSN"] = dsn
    environment["ODBC_BENCH_DRIVER_DSN"] = dsn
    destination = output_directory or PROJECT_ROOT / "artifacts" / "driver_matrix"
    destination.mkdir(parents=True, exist_ok=True)
    reports = []
    for mode, runner in (("async", run_odbc_async_benchmark), ("streaming", run_odbc_streaming_benchmark)):
        log = destination / f"driver_matrix_{driver_slug}_{mode}.log"
        code, metrics, _ = runner(package_root=package_root, log_path=log, environment=environment)
        reports.append({"mode": mode, "exit_code": code, "status": "pass" if code == 0 else ("inconclusive" if code == 2 else "fail"), "metrics": metrics, "log_file": log.name})
    write_json(destination / f"{driver_slug}_summary.json", {"matrix_version": 1, "driver": driver_name, "scenarios": reports})
    if any(report["exit_code"] != 0 for report in reports):
        raise RuntimeError(f"{driver_name}: one or more benchmark scenarios failed or are inconclusive")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run ODBC driver benchmark matrix.")
    parser.add_argument("--env-path", default=".env")
    parser.add_argument("--output-directory", default="", help="Directory for per-driver logs")
    args = parser.parse_args()

    import_dotenv_if_present(resolve_env_path(args.env_path))
    output_directory = Path(args.output_directory) if args.output_directory else None

    drivers = [
        {
            "name": "SQL Anywhere",
            "slug": "sql_anywhere",
            "dsn": get_effective_env_value(("ODBC_TEST_DSN", "ODBC_DSN")),
        },
        {
            "name": "SQL Server",
            "slug": "sql_server",
            "dsn": get_effective_env_value(("ODBC_TEST_DSN_SQL_SERVER", "ODBC_DSN_SQL_SERVER")),
        },
        {
            "name": "PostgreSQL",
            "slug": "postgresql",
            "dsn": get_effective_env_value(
                ("ODBC_TEST_DSN_POSTGRESQL", "ODBC_DSN_POSTGRESQL")
            ),
        },
    ]

    configured = sum(1 for driver in drivers if driver["dsn"])
    print("Running ODBC driver benchmark matrix")
    print(f"Configured drivers: {configured}")

    if configured == 0:
        print("No DSN configured; nothing to benchmark.")
        return 2

    failed = False
    for driver in drivers:
        try:
            run_benchmark_for_driver(
                driver_name=driver["name"],
                driver_slug=driver["slug"],
                dsn=driver["dsn"],
                output_directory=output_directory,
            )
        except RuntimeError as error:
            print(str(error), file=sys.stderr)
            failed = True
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
