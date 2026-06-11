#!/usr/bin/env python3
from __future__ import annotations

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


def invoke_benchmark(script_name: str, output_directory: Path | None) -> int:
    script_path = TOOL_DIR / script_name
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

    previous_dsn = os.environ.get("ODBC_TEST_DSN")
    previous_stream_query = os.environ.get("ODBC_STREAM_BENCH_QUERY")
    try:
        os.environ["ODBC_TEST_DSN"] = dsn
        os.environ.pop("ODBC_STREAM_BENCH_QUERY", None)

        if output_directory is None:
            async_exit = invoke_benchmark("odbc_async_benchmark.py", None)
            if async_exit != 0:
                raise RuntimeError(f"{driver_name} async benchmark failed")
            stream_exit = invoke_benchmark("odbc_streaming_benchmark.py", None)
            if stream_exit != 0:
                raise RuntimeError(f"{driver_name} streaming benchmark failed")
            return

        output_directory.mkdir(parents=True, exist_ok=True)
        async_log = output_directory / f"driver_matrix_{driver_slug}_async.log"
        stream_log = output_directory / f"driver_matrix_{driver_slug}_streaming.log"

        async_exit = run_streaming(
            [sys.executable, str(TOOL_DIR / "odbc_async_benchmark.py")],
            cwd=PROJECT_ROOT,
            log_path=async_log,
        )
        if async_exit != 0:
            raise RuntimeError(f"{driver_name} async benchmark failed")

        stream_exit = run_streaming(
            [sys.executable, str(TOOL_DIR / "odbc_streaming_benchmark.py")],
            cwd=PROJECT_ROOT,
            log_path=stream_log,
        )
        if stream_exit != 0:
            raise RuntimeError(f"{driver_name} streaming benchmark failed")
    finally:
        if previous_dsn is None:
            os.environ.pop("ODBC_TEST_DSN", None)
        else:
            os.environ["ODBC_TEST_DSN"] = previous_dsn
        if previous_stream_query is None:
            os.environ.pop("ODBC_STREAM_BENCH_QUERY", None)
        else:
            os.environ["ODBC_STREAM_BENCH_QUERY"] = previous_stream_query


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
        return 0

    for driver in drivers:
        run_benchmark_for_driver(
            driver_name=driver["name"],
            driver_slug=driver["slug"],
            dsn=driver["dsn"],
            output_directory=output_directory,
        )
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except RuntimeError as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
