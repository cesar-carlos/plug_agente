from __future__ import annotations

import os
import re
import time
from pathlib import Path
from typing import Mapping

from tool.py.benchmark_common import parse_odbc_benchmark_metrics, valid_native_benchmark_report, extract_json_object_from_output
from tool.py.odbc_benchmark_gate import (
    enforce_async_benchmark_gates,
    enforce_streaming_benchmark_gates,
)
from tool.py.script_utils import (
    get_dsn_driver_family,
    resolve_benchmark_package,
    run_streaming,
)

DEFAULT_ASYNC_BENCHMARK = "tool/benchmarks/native_odbc_benchmark.dart"
DEFAULT_STREAMING_BENCHMARK = DEFAULT_ASYNC_BENCHMARK


def _resolve_benchmark_dsn(environment: Mapping[str, str]) -> str:
    for key in (
        "ODBC_BENCH_DRIVER_DSN",
        "ODBC_TEST_DSN_SQL_SERVER",
        "ODBC_DSN_SQL_SERVER",
        "ODBC_TEST_DSN",
        "ODBC_DSN",
    ):
        value = environment.get(key, "").strip()
        if value:
            return value
    return ""


def _apply_benchmark_dsn_preference(environment: dict[str, str]) -> str:
    """Prefer SQL Server DSN for ODBC example benchmarks when configured."""
    dsn = _resolve_benchmark_dsn(environment)
    if dsn:
        environment["ODBC_TEST_DSN"] = dsn
    return dsn


def resolve_benchmark_driver_family(environment: Mapping[str, str] | None = None) -> str:
    """Return the non-sensitive driver family selected by the benchmark DSN policy."""

    selected_environment = os.environ if environment is None else environment
    return get_dsn_driver_family(_resolve_benchmark_dsn(selected_environment))


def _reset_benchmark_log(log_path: Path) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    log_path.write_text("", encoding="utf-8")


def _native_environment(package_root: Path, source: Mapping[str, str] | None = None) -> dict[str, str]:
    environment = dict(os.environ if source is None else source)
    # The native benchmark runs in this repository, using its locked package.
    # Make the published binary discoverable without editing the package cache.
    version_match = re.search(r"^version:\s*([^\s#]+)", (package_root / "pubspec.yaml").read_text(), re.MULTILINE)
    home = environment.get("USERPROFILE") or environment.get("HOME")
    if version_match and home:
        platform_dir = "windows_x64" if os.name == "nt" else "linux_x64"
        artifact = Path(home) / ".cache" / "odbc_fast" / version_match.group(1) / platform_dir
        library = "odbc_engine.dll" if os.name == "nt" else "libodbc_engine.so"
        if (artifact / library).is_file():
            path_key = "PATH" if os.name == "nt" else "LD_LIBRARY_PATH"
            environment[path_key] = str(artifact) + os.pathsep + environment.get(path_key, "")
    return environment


def run_odbc_async_benchmark(
    *,
    package_root: Path,
    log_path: Path,
    extra_args: list[str] | None = None,
    benchmark_path: Path | None = None,
    environment: Mapping[str, str] | None = None,
) -> tuple[int, dict[str, float], str]:
    benchmark_environment = _native_environment(package_root, environment)
    dsn = _apply_benchmark_dsn_preference(benchmark_environment)
    benchmark_environment["ODBC_BENCH_REPRO_DIR"] = str(log_path.parent / "native_reproducer")
    benchmark_file = benchmark_path or Path(__file__).resolve().parents[2] / DEFAULT_ASYNC_BENCHMARK
    execution_root, _, relative_path = resolve_benchmark_package(benchmark_file)
    _reset_benchmark_log(log_path)
    started = time.perf_counter()
    exit_code = run_streaming(
        ["dart", "run", relative_path, "--mode", "async", *(extra_args or [])],
        cwd=execution_root,
        env=benchmark_environment,
        log_path=log_path,
    )
    wall_ms = (time.perf_counter() - started) * 1000.0
    output = log_path.read_text(encoding="utf-8") if log_path.is_file() else ""
    metrics = parse_odbc_benchmark_metrics(output)
    metrics["wall_ms"] = wall_ms
    if exit_code == 0:
        if not valid_native_benchmark_report(output, 'async') or extract_json_object_from_output(output).get('repeats') != 9:
            return 2, metrics, output
        gate_exit = enforce_async_benchmark_gates(output, environment=benchmark_environment)
        if gate_exit != 0:
            return gate_exit, metrics, output
    if exit_code == 0:
        from tool.py.odbc_benchmark_gate import parse_async_benchmark_scenarios
        scenarios = parse_async_benchmark_scenarios(output)
        required = {"workerCount=1", "workerCount=4", "workerCount=4 columnar", "workerCount=4 columnar compressed", "native pool", "prepared reuse"}
        if not required.issubset({row.label for row in scenarios}):
            return 2, metrics, output
    return exit_code, metrics, output


def run_odbc_streaming_benchmark(
    *,
    package_root: Path,
    log_path: Path,
    extra_args: list[str] | None = None,
    benchmark_path: Path | None = None,
    environment: Mapping[str, str] | None = None,
) -> tuple[int, dict[str, float], str]:
    benchmark_environment = _native_environment(package_root, environment)
    dsn = _apply_benchmark_dsn_preference(benchmark_environment)
    benchmark_file = benchmark_path or Path(__file__).resolve().parents[2] / DEFAULT_STREAMING_BENCHMARK
    execution_root, _, relative_path = resolve_benchmark_package(benchmark_file)
    _reset_benchmark_log(log_path)
    started = time.perf_counter()
    exit_code = run_streaming(
        ["dart", "run", relative_path, "--mode", "streaming", *(extra_args or [])],
        cwd=execution_root,
        env=benchmark_environment,
        log_path=log_path,
    )
    output = log_path.read_text(encoding="utf-8") if log_path.is_file() else ""
    wall_ms = (time.perf_counter() - started) * 1000.0
    metrics = parse_odbc_benchmark_metrics(output)
    metrics["wall_ms"] = wall_ms
    if exit_code == 0:
        from tool.py.benchmark_common import parse_odbc_streaming_benchmark_metrics

        stream_metrics = parse_odbc_streaming_benchmark_metrics(output)
        metrics.update(stream_metrics)
        if not valid_native_benchmark_report(output, 'streaming') or extract_json_object_from_output(output).get('repeats') != 9:
            return 2, metrics, output
        if any(stream_metrics.get(f"{label}.rows", 0) <= 0 for label in ("streamQueryBuffer", "streamQueryBatched")):
            return 2, metrics, output
        if stream_metrics['streamQueryBuffer.rows'] != stream_metrics['streamQueryBatched.rows']:
            return 2, metrics, output
        gate_exit = enforce_streaming_benchmark_gates(output, environment=benchmark_environment)
        if gate_exit != 0:
            return gate_exit, metrics, output
    return exit_code, metrics, output
