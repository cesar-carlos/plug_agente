#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

from py.script_utils import (
    PROJECT_ROOT,
    forward_script_args,
    import_dotenv_if_present,
    resolve_benchmark_package,
    resolve_env_path,
    run_streaming,
)


DEFAULT_BENCHMARK = Path(r"D:\Developer\dart_odbc_fast\example\async_concurrency_benchmark.dart")


def main() -> int:
    parser = argparse.ArgumentParser(description="Run odbc_fast async concurrency benchmark.")
    parser.add_argument(
        "--benchmark-path",
        default=str(DEFAULT_BENCHMARK),
        help="Path to async_concurrency_benchmark.dart",
    )
    parser.add_argument("--env-path", default=".env", help="Dotenv file to load when vars are unset")
    args, remainder = parser.parse_known_args()

    package_root, resolved_benchmark, relative_path = resolve_benchmark_package(
        Path(args.benchmark_path)
    )
    import_dotenv_if_present(resolve_env_path(args.env_path))

    if not os.environ.get("ODBC_TEST_DSN") and os.environ.get("ODBC_DSN"):
        os.environ["ODBC_TEST_DSN"] = os.environ["ODBC_DSN"]

    print("Running odbc_fast async concurrency benchmark")
    print(f"Benchmark: {resolved_benchmark}")
    print(f"Package root: {package_root}")
    print(f"ODBC_TEST_DSN configured: {bool(os.environ.get('ODBC_TEST_DSN'))}")
    print(f"ODBC_POOL_SIZE={os.environ.get('ODBC_POOL_SIZE', '')}")
    print(f"ODBC_ASYNC_WORKER_COUNT={os.environ.get('ODBC_ASYNC_WORKER_COUNT', '')}")
    print(
        "ODBC_ASYNC_MAX_PENDING_REQUESTS="
        f"{os.environ.get('ODBC_ASYNC_MAX_PENDING_REQUESTS', '')}"
    )

    benchmark_args = forward_script_args(remainder)
    return run_streaming(["dart", "run", relative_path, *benchmark_args], cwd=package_root)


if __name__ == "__main__":
    raise SystemExit(main())
