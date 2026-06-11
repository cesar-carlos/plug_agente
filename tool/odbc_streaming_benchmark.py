#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
import warnings
from pathlib import Path

from py.script_utils import (
    forward_script_args,
    get_dsn_driver_family,
    get_long_query_for_driver,
    import_dotenv_if_present,
    resolve_benchmark_package,
    resolve_env_path,
    run_streaming,
)


DEFAULT_BENCHMARK = Path(r"D:\Developer\dart_odbc_fast\example\streaming_performance_benchmark.dart")


def invoke_dart_benchmark(
    package_root: Path,
    relative_path: str,
    benchmark_args: list[str],
) -> tuple[int, None]:
    exit_code = run_streaming(
        ["dart", "run", relative_path, *benchmark_args],
        cwd=package_root,
    )
    return exit_code, None


def main() -> int:
    parser = argparse.ArgumentParser(description="Run odbc_fast streaming benchmark.")
    parser.add_argument(
        "--benchmark-path",
        default=str(DEFAULT_BENCHMARK),
        help="Path to streaming_performance_benchmark.dart",
    )
    parser.add_argument("--env-path", default=".env", help="Dotenv file to load when vars are unset")
    args, remainder = parser.parse_known_args()

    package_root, resolved_benchmark, relative_path = resolve_benchmark_package(
        Path(args.benchmark_path)
    )
    import_dotenv_if_present(resolve_env_path(args.env_path))

    if not os.environ.get("ODBC_TEST_DSN") and os.environ.get("ODBC_DSN"):
        os.environ["ODBC_TEST_DSN"] = os.environ["ODBC_DSN"]

    stream_query_source = "explicit"
    if not os.environ.get("ODBC_STREAM_BENCH_QUERY"):
        driver_family = get_dsn_driver_family(os.environ.get("ODBC_TEST_DSN", ""))
        long_query = get_long_query_for_driver(driver_family)
        if long_query:
            os.environ["ODBC_STREAM_BENCH_QUERY"] = long_query
            stream_query_source = f"ODBC_INTEGRATION_LONG_QUERY ({driver_family})"
        else:
            stream_query_source = "benchmark_default"

    print("Running odbc_fast streaming benchmark")
    print(f"Benchmark: {resolved_benchmark}")
    print(f"Package root: {package_root}")
    print(f"ODBC_TEST_DSN configured: {bool(os.environ.get('ODBC_TEST_DSN'))}")
    print(f"ODBC_STREAM_BENCH_QUERY={os.environ.get('ODBC_STREAM_BENCH_QUERY', '')}")
    print(f"ODBC_STREAM_BENCH_QUERY_SOURCE={stream_query_source}")
    print(f"ODBC_STREAM_BENCH_FETCH_SIZE={os.environ.get('ODBC_STREAM_BENCH_FETCH_SIZE', '')}")
    print(f"ODBC_STREAM_BENCH_CHUNK_SIZE={os.environ.get('ODBC_STREAM_BENCH_CHUNK_SIZE', '')}")

    benchmark_args = forward_script_args(remainder)
    exit_code, _ = invoke_dart_benchmark(package_root, relative_path, benchmark_args)
    if exit_code == 0:
        return 0

    if stream_query_source != "explicit":
        warnings.warn(
            "Streaming benchmark failed with auto-selected long query; retrying with package default query."
        )
        os.environ.pop("ODBC_STREAM_BENCH_QUERY", None)
        fallback_exit, _ = invoke_dart_benchmark(package_root, relative_path, benchmark_args)
        return fallback_exit

    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
