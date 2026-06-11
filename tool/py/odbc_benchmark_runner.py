from __future__ import annotations

import os
import time
from pathlib import Path

from tool.py.benchmark_common import parse_odbc_benchmark_metrics
from tool.py.script_utils import get_long_query_for_driver, resolve_benchmark_package, run_streaming

DEFAULT_ASYNC_BENCHMARK = "example/async_concurrency_benchmark.dart"
DEFAULT_STREAMING_BENCHMARK = "example/streaming_performance_benchmark.dart"


def _resolve_benchmark_file(package_root: Path, relative_path: str) -> Path:
    benchmark_path = package_root / relative_path
    if not benchmark_path.is_file():
        raise FileNotFoundError(f"ODBC benchmark not found: {benchmark_path}")
    return benchmark_path


def _prepare_stream_query() -> str:
    if os.environ.get("ODBC_STREAM_BENCH_QUERY", "").strip():
        return "explicit"
    dsn = os.environ.get("ODBC_TEST_DSN", "")
    driver_family = ""
    if dsn:
        from tool.py.script_utils import get_dsn_driver_family

        driver_family = get_dsn_driver_family(dsn)
    long_query = get_long_query_for_driver(driver_family)
    if long_query:
        os.environ["ODBC_STREAM_BENCH_QUERY"] = long_query
        return f"ODBC_INTEGRATION_LONG_QUERY ({driver_family})"
    return "benchmark_default"


def run_odbc_async_benchmark(
    *,
    package_root: Path,
    log_path: Path,
    extra_args: list[str] | None = None,
) -> tuple[int, dict[str, float], str]:
    benchmark_file = _resolve_benchmark_file(package_root, DEFAULT_ASYNC_BENCHMARK)
    _, _, relative_path = resolve_benchmark_package(benchmark_file)
    started = time.perf_counter()
    exit_code = run_streaming(
        ["dart", "run", relative_path, *(extra_args or [])],
        cwd=package_root,
        log_path=log_path,
    )
    wall_ms = (time.perf_counter() - started) * 1000.0
    output = log_path.read_text(encoding="utf-8") if log_path.is_file() else ""
    metrics = parse_odbc_benchmark_metrics(output)
    metrics["wall_ms"] = wall_ms
    return exit_code, metrics, output


def run_odbc_streaming_benchmark(
    *,
    package_root: Path,
    log_path: Path,
    extra_args: list[str] | None = None,
) -> tuple[int, dict[str, float], str]:
    benchmark_file = _resolve_benchmark_file(package_root, DEFAULT_STREAMING_BENCHMARK)
    _, _, relative_path = resolve_benchmark_package(benchmark_file)
    query_source = _prepare_stream_query()
    started = time.perf_counter()
    exit_code = run_streaming(
        ["dart", "run", relative_path, *(extra_args or [])],
        cwd=package_root,
        log_path=log_path,
    )
    output = log_path.read_text(encoding="utf-8") if log_path.is_file() else ""
    if exit_code != 0 and query_source != "explicit":
        os.environ.pop("ODBC_STREAM_BENCH_QUERY", None)
        started = time.perf_counter()
        exit_code = run_streaming(
            ["dart", "run", relative_path, *(extra_args or [])],
            cwd=package_root,
            log_path=log_path,
        )
        output = log_path.read_text(encoding="utf-8") if log_path.is_file() else ""
    wall_ms = (time.perf_counter() - started) * 1000.0
    metrics = parse_odbc_benchmark_metrics(output)
    metrics["wall_ms"] = wall_ms
    return exit_code, metrics, output
