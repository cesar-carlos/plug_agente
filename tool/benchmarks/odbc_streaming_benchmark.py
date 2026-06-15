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
import sys
import warnings
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.py.benchmark_common import bootstrap_env, resolve_dart_odbc_fast_root
from tool.py.odbc_benchmark_runner import (
    _apply_benchmark_dsn_preference,
    _prepare_stream_query,
    run_odbc_streaming_benchmark,
)
from tool.py.script_utils import PROJECT_ROOT, forward_script_args, resolve_env_path


DEFAULT_BENCHMARK = Path(r"D:\Developer\dart_odbc_fast\example\streaming_performance_benchmark.dart")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run odbc_fast streaming benchmark.")
    parser.add_argument(
        "--benchmark-path",
        default=str(DEFAULT_BENCHMARK),
        help="Path to streaming_performance_benchmark.dart",
    )
    parser.add_argument("--env-path", default=".env", help="Dotenv file to load when vars are unset")
    args, remainder = parser.parse_known_args()

    bootstrap_env(resolve_env_path(args.env_path))
    package_root = resolve_dart_odbc_fast_root()
    if package_root is None:
        print("DART_ODBC_FAST_ROOT not found.", file=sys.stderr)
        return 2

    stream_dsn = _apply_benchmark_dsn_preference()
    stream_query_source = _prepare_stream_query(stream_dsn)

    print("Running odbc_fast streaming benchmark")
    print(f"Benchmark: {Path(args.benchmark_path).resolve()}")
    print(f"Package root: {package_root}")
    print(f"ODBC_TEST_DSN configured: {bool(os.environ.get('ODBC_TEST_DSN'))}")
    print(f"ODBC_STREAM_BENCH_QUERY={os.environ.get('ODBC_STREAM_BENCH_QUERY', '')}")
    print(f"ODBC_STREAM_BENCH_QUERY_SOURCE={stream_query_source}")
    print(f"ODBC_STREAM_BENCH_FETCH_SIZE={os.environ.get('ODBC_STREAM_BENCH_FETCH_SIZE', '')}")
    print(f"ODBC_STREAM_BENCH_CHUNK_SIZE={os.environ.get('ODBC_STREAM_BENCH_CHUNK_SIZE', '')}")

    exit_code, _metrics, _output = run_odbc_streaming_benchmark(
        package_root=package_root,
        log_path=PROJECT_ROOT / "artifacts" / "odbc_streaming_benchmark.log",
        extra_args=forward_script_args(remainder),
    )
    if exit_code != 0 and stream_query_source != "explicit":
        warnings.warn(
            "Streaming benchmark failed with auto-selected long query; "
            "retry is handled inside odbc_benchmark_runner.",
        )
    return exit_code


if __name__ == "__main__":
    raise SystemExit(main())
