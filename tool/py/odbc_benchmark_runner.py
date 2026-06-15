from __future__ import annotations

import os
import time
from pathlib import Path

from tool.py.benchmark_common import parse_odbc_benchmark_metrics
from tool.py.odbc_benchmark_gate import (
    enforce_async_benchmark_gates,
    enforce_streaming_benchmark_gates,
    _benchmark_gates_enabled,
)
from tool.py.script_utils import get_long_query_for_driver, resolve_benchmark_package, run_streaming

DEFAULT_ASYNC_BENCHMARK = "example/async_concurrency_benchmark.dart"
DEFAULT_STREAMING_BENCHMARK = "example/streaming_performance_benchmark.dart"


def _resolve_benchmark_dsn() -> str:
    for key in (
        "ODBC_TEST_DSN_SQL_SERVER",
        "ODBC_DSN_SQL_SERVER",
        "ODBC_TEST_DSN",
        "ODBC_DSN",
    ):
        value = os.environ.get(key, "").strip()
        if value:
            return value
    return ""


def _apply_benchmark_dsn_preference() -> str:
    """Prefer SQL Server DSN for ODBC example benchmarks when configured."""
    dsn = _resolve_benchmark_dsn()
    if dsn:
        os.environ["ODBC_TEST_DSN"] = dsn
    return dsn


def _prepare_async_query(dsn: str) -> str:
    if os.environ.get("ODBC_BENCH_QUERY", "").strip():
        return "explicit"
    if not dsn:
        return "benchmark_default"
    from tool.py.script_utils import get_dsn_driver_family

    driver_family = get_dsn_driver_family(dsn)
    long_query = get_long_query_for_driver(driver_family)
    if long_query and _benchmark_gates_enabled() and driver_family == "SQL Server":
        long_query = (
            "SELECT TOP 8000 object_id, name, type, type_desc, modify_date "
            "FROM sys.objects ORDER BY object_id"
        )
    if long_query:
        os.environ["ODBC_BENCH_QUERY"] = long_query
        return f"ODBC_INTEGRATION_LONG_QUERY ({driver_family})"
    return "benchmark_default"


def _reset_benchmark_log(log_path: Path) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text("", encoding="utf-8")


def _prepare_stream_query(dsn: str) -> str:
    if os.environ.get("ODBC_STREAM_BENCH_QUERY", "").strip():
        return "explicit"
    if not dsn:
        return "benchmark_default"
    from tool.py.script_utils import get_dsn_driver_family

    driver_family = get_dsn_driver_family(dsn)
    long_query = get_long_query_for_driver(driver_family)
    if long_query and _benchmark_gates_enabled() and driver_family == "SQL Server":
        long_query = (
            "SELECT TOP 8000 object_id, name, type, type_desc, modify_date "
            "FROM sys.objects ORDER BY object_id"
        )
    if long_query:
        os.environ["ODBC_STREAM_BENCH_QUERY"] = long_query
        return f"ODBC_INTEGRATION_LONG_QUERY ({driver_family})"
    return "benchmark_default"


def _resolve_benchmark_file(package_root: Path, relative_path: str) -> Path:
    benchmark_path = package_root / relative_path
    if not benchmark_path.is_file():
        raise FileNotFoundError(f"ODBC benchmark not found: {benchmark_path}")
    return benchmark_path


def run_odbc_async_benchmark(
    *,
    package_root: Path,
    log_path: Path,
    extra_args: list[str] | None = None,
) -> tuple[int, dict[str, float], str]:
    dsn = _apply_benchmark_dsn_preference()
    query_source = _prepare_async_query(dsn)
    benchmark_file = _resolve_benchmark_file(package_root, DEFAULT_ASYNC_BENCHMARK)
    _, _, relative_path = resolve_benchmark_package(benchmark_file)
    _reset_benchmark_log(log_path)
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
    if exit_code == 0:
        gate_exit = enforce_async_benchmark_gates(output)
        if gate_exit != 0:
            return gate_exit, metrics, output
    elif query_source != "explicit":
        os.environ.pop("ODBC_BENCH_QUERY", None)
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
        if exit_code == 0:
            gate_exit = enforce_async_benchmark_gates(output)
            if gate_exit != 0:
                return gate_exit, metrics, output
    return exit_code, metrics, output


def run_odbc_streaming_benchmark(
    *,
    package_root: Path,
    log_path: Path,
    extra_args: list[str] | None = None,
) -> tuple[int, dict[str, float], str]:
    dsn = _apply_benchmark_dsn_preference()
    query_source = _prepare_stream_query(dsn)
    benchmark_file = _resolve_benchmark_file(package_root, DEFAULT_STREAMING_BENCHMARK)
    _, _, relative_path = resolve_benchmark_package(benchmark_file)
    _reset_benchmark_log(log_path)
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
    if exit_code == 0:
        gate_exit = enforce_streaming_benchmark_gates(output)
        if gate_exit != 0:
            return gate_exit, metrics, output
    return exit_code, metrics, output
