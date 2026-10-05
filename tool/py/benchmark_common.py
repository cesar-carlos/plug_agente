from __future__ import annotations

import json
import hashlib
import math
import os
import platform
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Collection, Mapping

from tool.py.script_utils import PROJECT_ROOT, get_dsn_driver_family, import_dotenv_if_present
from tool.py.script_utils import resolve_command

SCHEMA_VERSION = 2
BENCHMARKS_DIR = PROJECT_ROOT / "benchmarks"
BASELINE_PATH = BENCHMARKS_DIR / "baseline" / "summary.json"
RESULTS_DIR = BENCHMARKS_DIR / "results"
HISTORY_DIR = BENCHMARKS_DIR / "history"
LEGACY_LOGS_DIR = PROJECT_ROOT / "benchmark_logs"
SCHEMA_PATH = BENCHMARKS_DIR / "schema" / "summary.schema.json"

SAFE_ENV_KEYS = (
    "ODBC_POOL_SIZE",
    "ODBC_ASYNC_WORKER_COUNT",
    "ODBC_ASYNC_MAX_PENDING_REQUESTS",
    "ODBC_STREAM_BENCH_FETCH_SIZE",
    "ODBC_STREAM_BENCH_CHUNK_SIZE",
    "RUN_LIVE_API_TESTS",
    "ODBC_E2E_DML_PERF_ROW_COUNT",
    "ODBC_E2E_DML_BULK_ROW_COUNT",
)

TIMING_TRIPLE_RE = re.compile(
    r"(?P<p50>[0-9.]+(?:ms|us)?)\s*/\s*(?P<p95>[0-9.]+(?:ms|us)?)\s*/\s*(?P<p99>[0-9.]+(?:ms|us)?)"
)

STREAMING_BENCHMARK_RESULT_RE = re.compile(
    r"(?P<label>streamQueryBatched|streamQueryBuffer|streamQuery):\s*"
    r"(?P<elapsed_ms>[0-9.]+)\s*ms,\s*"
    r"rows=(?P<rows>\d+),\s*chunks=(?P<chunks>\d+),\s*"
    r"rowsPerSecond=(?P<rows_per_second>[0-9.]+),\s*"
    r"fetchSize=(?P<fetch_size>\d+),\s*chunkSize=(?P<chunk_size>\d+)",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class SuitePlan:
    suite_id: str
    kind: str
    command: list[str]
    cwd: Path
    enabled: bool
    skip_reason: str | None = None


def run_id_now() -> str:
    return datetime.now().astimezone().strftime("%Y%m%d_%H%M%S")


def captured_at_now() -> str:
    return datetime.now().astimezone().isoformat(timespec="seconds")


def collect_git_metadata() -> dict[str, Any]:
    def _run_git(args: list[str]) -> str:
        try:
            result = subprocess.run(
                ["git", *args],
                cwd=PROJECT_ROOT,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                check=False,
            )
            if result.returncode == 0 and result.stdout:
                return result.stdout.strip()
        except (OSError, subprocess.SubprocessError):
            pass
        return "(not resolved)"

    dirty = False
    try:
        status = subprocess.run(
            ["git", "status", "--porcelain"],
            cwd=PROJECT_ROOT,
            capture_output=True,
            text=True,
            encoding="utf-8",
            errors="replace",
            check=False,
        )
        dirty = bool(status.stdout and status.stdout.strip())
    except (OSError, subprocess.SubprocessError):
        pass

    return {
        "commit_sha": _run_git(["rev-parse", "HEAD"]),
        "branch": _run_git(["rev-parse", "--abbrev-ref", "HEAD"]),
        "dirty": dirty,
        "source_sha256": collect_source_identity(PROJECT_ROOT)['source_sha256'],
    }


def collect_source_identity(root: Path, *, revision: str | None = None) -> dict[str, str]:
    digest = hashlib.sha256()
    files = sorted((root / 'lib').rglob('*.dart')) + [root / 'pubspec.yaml', root / 'pubspec.lock']
    for path in files:
        digest.update(path.relative_to(root).as_posix().encode())
        digest.update(path.read_bytes())
    if revision is None:
        revision = subprocess.run(['git', 'rev-parse', 'HEAD'], cwd=root, text=True, capture_output=True, check=True).stdout.strip()
    return {'commit_sha': revision, 'source_sha256': digest.hexdigest()}


def collect_dependency_versions(root: Path) -> dict[str, str]:
    versions = {}
    package = None
    for line in (root / 'pubspec.lock').read_text(encoding='utf-8').splitlines():
        if line.startswith('  ') and not line.startswith('    ') and line.endswith(':'):
            package = line.strip().removesuffix(':')
        elif package and line.startswith('    version:'):
            versions[package] = line.partition(':')[2].strip().strip('"\'')
    return versions


def collect_dependency_provenance(root: Path) -> dict[str, str]:
    """Compare the entire lock entry, including source, hash and Git revision."""
    entries: dict[str, str] = {}
    package = None
    lines: list[str] = []
    for line in (root / 'pubspec.lock').read_text(encoding='utf-8').splitlines():
        if line.startswith('  ') and not line.startswith('    ') and line.endswith(':'):
            if package:
                entries[package] = '\n'.join(lines)
            package, lines = line.strip().removesuffix(':'), []
        elif package and line.startswith('    '):
            lines.append(line.strip())
        elif package and line and not line.startswith(' '):
            entries[package] = '\n'.join(lines)
            package = None
    if package:
        entries[package] = '\n'.join(lines)
    return entries


def collect_machine_metadata() -> dict[str, str]:
    metadata = {
        "platform": platform.platform(),
        "machine": platform.machine(),
        "processor": platform.processor() or "(unknown)",
        "python_version": platform.python_version(),
    }
    for executable in ("dart", "flutter"):
        result = subprocess.run(resolve_command([executable, "--version"]), capture_output=True, text=True, encoding='utf-8', errors='replace')
        metadata[f"{executable}_version"] = (result.stdout or result.stderr).strip()
    metadata["dependencies_sha256"] = hashlib.sha256(json.dumps(collect_dependency_versions(PROJECT_ROOT), sort_keys=True).encode()).hexdigest()
    metadata["host_fingerprint"] = hashlib.sha256(platform.node().encode()).hexdigest()
    return metadata


def odbc_dsn_configured() -> bool:
    for key in (
        "ODBC_TEST_DSN_SQL_SERVER",
        "ODBC_DSN_SQL_SERVER",
        "ODBC_TEST_DSN",
        "ODBC_DSN",
    ):
        value = os.environ.get(key, "").strip()
        if value:
            return True
    return False


def collect_env_flags() -> dict[str, Any]:
    flags: dict[str, Any] = {
        "odbc_test_dsn_configured": odbc_dsn_configured(),
    }
    if odbc_dsn_configured():
        dsn = os.environ.get("ODBC_TEST_DSN") or os.environ.get("ODBC_DSN") or ""
        flags["odbc_driver_family"] = get_dsn_driver_family(dsn)

    for key in SAFE_ENV_KEYS:
        raw = os.environ.get(key)
        if raw is None or not str(raw).strip():
            continue
        value = str(raw).strip()
        if value.lower() in {"true", "false"}:
            flags[key.lower()] = value.lower() == "true"
        else:
            try:
                if "." in value:
                    flags[key.lower()] = float(value)
                else:
                    flags[key.lower()] = int(value)
            except ValueError:
                flags[key.lower()] = "invalid"
            if isinstance(flags[key.lower()], float) and not math.isfinite(flags[key.lower()]):
                flags[key.lower()] = "invalid"
    return flags


def resolve_dart_odbc_fast_root(*, prepare_native: bool = True) -> Path | None:
    candidates: list[Path] = []
    env_root = os.environ.get("DART_ODBC_FAST_ROOT", "").strip()
    if env_root:
        candidates.append(Path(env_root))
    lock = PROJECT_ROOT / 'pubspec.lock'
    if lock.exists():
        block = re.search(r'^  odbc_fast:\n(.*?)(?=^  \w|^sdks:)', lock.read_text(encoding='utf-8'), re.M | re.S)
        if block and 'source: git' in block[1]:
            if not prepare_native:
                revision = re.search(r'resolved-ref: ["\']?([0-9a-f]{40})', block[1])
                if not revision:
                    raise ValueError('A full native Git revision is required')
                return PROJECT_ROOT / 'build/odbc-native' / revision[1] / 'source'
            from tool.odbc.build_pinned_native import build_pinned_native
            # Benchmarks may create .dart_tool files. Run the exported workspace
            # source, never the read-only checkout inside the global Pub cache.
            binary = build_pinned_native(PROJECT_ROOT)
            os.environ['ODBC_FAST_NATIVE_LIBRARY'] = str(binary)
            return binary.parent / 'source'
    locked_version = _resolve_locked_odbc_fast_version()
    if locked_version:
        candidates.extend(_published_odbc_fast_candidates(locked_version))
    candidates.extend(
        [
            Path(r"D:\Developer\dart_odbc_fast"),
            PROJECT_ROOT.parent / "dart_odbc_fast",
        ]
    )
    for candidate in candidates:
        if (candidate / "pubspec.yaml").is_file():
            return candidate.resolve()
    return None


def _resolve_locked_odbc_fast_version() -> str | None:
    lockfile = PROJECT_ROOT / "pubspec.lock"
    if not lockfile.is_file():
        return None

    in_odbc_fast_section = False
    for line in lockfile.read_text(encoding="utf-8").splitlines():
        if line.startswith("  odbc_fast:"):
            in_odbc_fast_section = True
            continue
        if in_odbc_fast_section and line.startswith("  ") and not line.startswith("    "):
            break
        if in_odbc_fast_section and line.strip().startswith("version:"):
            return line.split(":", 1)[1].strip().strip('"').strip("'")
    return None


def _published_odbc_fast_candidates(version: str) -> list[Path]:
    cache_roots: list[Path] = []
    configured_cache = os.environ.get("PUB_CACHE", "").strip()
    if configured_cache:
        cache_roots.append(Path(configured_cache))
    local_app_data = os.environ.get("LOCALAPPDATA", "").strip()
    if local_app_data:
        cache_roots.append(Path(local_app_data) / "Pub" / "Cache")
    try:
        cache_roots.append(Path.home() / ".pub-cache")
    except RuntimeError:
        pass

    package_name = f"odbc_fast-{version}"
    return [cache_root / "hosted" / "pub.dev" / package_name for cache_root in cache_roots]


def strip_shell_log_prefix(line: str) -> str:
    candidate = line.strip()
    if candidate.startswith("Shell:"):
        return candidate[len("Shell:") :].strip()
    return candidate


def is_dart_ffi_compile_failure(exit_code: int, output: str) -> bool:
    if exit_code == 252:
        return True
    markers = ("InvalidType", "_FfiUseSiteTransformer")
    return any(marker in output for marker in markers)


def parse_transport_markdown_metrics(output: str) -> dict[str, float]:
    metrics: dict[str, float] = {}
    for line in output.splitlines():
        candidate = strip_shell_log_prefix(line)
        if not candidate.startswith("|") or candidate.startswith("| ---"):
            continue
        if "case |" in candidate.lower() or "send p50" in candidate.lower():
            continue

        parts = [part.strip() for part in candidate.strip("|").split("|")]
        if len(parts) < 10:
            continue

        case = parts[0]
        path = parts[1]
        mode = parts[2]
        signed = parts[3].lower() == "true"
        prefix = f"{case}.{path}.{mode}.signed_{signed}"

        send_match = TIMING_TRIPLE_RE.search(parts[8] if len(parts) > 8 else "")
        receive_match = TIMING_TRIPLE_RE.search(parts[9] if len(parts) > 9 else "")
        if send_match:
            metrics[f"{prefix}.send_p50_us"] = _timing_to_micros(send_match.group("p50"))
            metrics[f"{prefix}.send_p95_us"] = _timing_to_micros(send_match.group("p95"))
            metrics[f"{prefix}.send_p99_us"] = _timing_to_micros(send_match.group("p99"))
        if receive_match:
            metrics[f"{prefix}.receive_p50_us"] = _timing_to_micros(receive_match.group("p50"))
            metrics[f"{prefix}.receive_p95_us"] = _timing_to_micros(receive_match.group("p95"))
            metrics[f"{prefix}.receive_p99_us"] = _timing_to_micros(receive_match.group("p99"))

        if len(parts) > 10 and parts[10].isdigit():
            metrics[f"{prefix}.isolate_operations"] = float(parts[10])
    return metrics


def parse_transport_json_metrics(payload: Mapping[str, Any]) -> dict[str, float]:
    metrics: dict[str, float] = {}
    path = str(payload.get("path", "unknown"))
    for result in payload.get("results", []):
        if not isinstance(result, dict):
            continue
        case = str(result.get("case", "unknown"))
        mode = str(result.get("requested_compression", "unknown"))
        signed = bool(result.get("signed"))
        prefix = f"{case}.{path}.{mode}.signed_{signed}"
        for key in (
            "send_p50_us",
            "send_p95_us",
            "send_p99_us",
            "receive_p50_us",
            "receive_p95_us",
            "receive_p99_us",
            "isolate_operations",
            "wire_bytes",
            "original_bytes",
            "bytes_saved",
        ):
            value = result.get(key)
            if isinstance(value, (int, float)):
                metrics[f"{prefix}.{key}"] = float(value)
    return metrics


def extract_json_object_from_output(output: str) -> dict[str, Any] | None:
    for line in reversed(output.splitlines()):
        candidate = line.strip()
        if candidate.startswith("Shell:"):
            candidate = candidate[len("Shell:") :].strip()
        if not candidate.startswith("{"):
            continue
        try:
            payload = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(payload, dict):
            return payload
    return None


def parse_plug_agente_stack_metrics(output: str) -> dict[str, float]:
    metrics: dict[str, float] = {}

    for line in output.splitlines():
        candidate = line.strip()
        if candidate.startswith("Shell:"):
            candidate = candidate[len("Shell:") :].strip()
        if candidate.startswith('{"benchmark":"plug_agente_stack"'):
            try:
                payload = json.loads(candidate)
            except json.JSONDecodeError:
                continue
            for row in payload.get("rows", []):
                if not isinstance(row, dict):
                    continue
                scenario = row.get("scenario")
                variant = row.get("variant")
                if not isinstance(scenario, str) or not isinstance(variant, str):
                    continue
                prefix = f"{scenario}.{variant}"
                median = row.get("median_us")
                if isinstance(median, (int, float)):
                    metrics[f"{prefix}.median_us"] = float(median)
                p95 = row.get("p95_us")
                if isinstance(p95, (int, float)):
                    metrics[f"{prefix}.p95_us"] = float(p95)
                speedup = row.get("speedup")
                if isinstance(speedup, (int, float)):
                    metrics[f"{prefix}.speedup"] = float(speedup)
                rows_per_sec = row.get("rows_per_sec")
                if isinstance(rows_per_sec, (int, float)):
                    metrics[f"{prefix}.rows_per_sec"] = float(rows_per_sec)
            continue

        if not candidate.startswith("|") or candidate.startswith("| ---"):
            continue
        if "scenario |" in candidate.lower():
            continue

        parts = [part.strip() for part in candidate.strip("|").split("|")]
        if len(parts) < 4:
            continue

        scenario = parts[0]
        variant = parts[1]
        prefix = f"{scenario}.{variant}"

        median = _parse_metric_cell(parts[3])
        if median is not None:
            metrics[f"{prefix}.median_us"] = median

        if len(parts) > 4:
            p95 = _parse_metric_cell(parts[4])
            if p95 is not None:
                metrics[f"{prefix}.p95_us"] = p95

        if len(parts) > 5:
            speedup = _parse_metric_cell(parts[5])
            if speedup is not None:
                metrics[f"{prefix}.speedup"] = speedup

        if len(parts) > 6:
            rows_per_sec = _parse_metric_cell(parts[6])
            if rows_per_sec is not None:
                metrics[f"{prefix}.rows_per_sec"] = rows_per_sec

    return metrics


def parse_gateway_encoding_metrics(output: str) -> dict[str, float]:
    metrics: dict[str, float] = {}
    payload = extract_json_object_from_output(output)
    if payload is None:
        return metrics

    for scenario in payload.get("scenarios", []):
        if not isinstance(scenario, dict):
            continue
        name = scenario.get("scenario")
        median = scenario.get("median_us")
        if isinstance(name, str) and isinstance(median, (int, float)):
            metrics[f"median_us_{name}"] = float(median)
            for key in ('rows', 'iterations'):
                if isinstance(scenario.get(key), (int, float)):
                    metrics[f'{name}.{key}'] = float(scenario[key])
    return metrics


def _parse_metric_cell(value: str) -> float | None:
    text = value.strip()
    if not text or text == "-":
        return None
    try:
        return float(text.replace(",", ""))
    except ValueError:
        return None


def parse_odbc_benchmark_metrics(output: str) -> dict[str, float]:
    metrics: dict[str, float] = {}
    patterns = {
        "wall_ms": re.compile(r"(?:wall|total)\s*(?:time)?\s*[:=]\s*([0-9.]+)\s*ms", re.I),
        "ops_per_sec": re.compile(r"([0-9.]+)\s+ops/s", re.I),
        "rows_per_sec": re.compile(r"([0-9.]+)\s+rows/s", re.I),
        "throughput_mbps": re.compile(r"([0-9.]+)\s+MB/s", re.I),
        "p50_ms": re.compile(r"p50\s*[:=]\s*([0-9.]+)\s*ms", re.I),
        "p95_ms": re.compile(r"p95\s*[:=]\s*([0-9.]+)\s*ms", re.I),
        "p99_ms": re.compile(r"p99\s*[:=]\s*([0-9.]+)\s*ms", re.I),
    }
    for name, pattern in patterns.items():
        matches = pattern.findall(output)
        if not matches:
            continue
        values = [float(value) for value in matches]
        metrics[name] = sum(values) / len(values)
        if len(values) > 1:
            metrics[f"{name}_max"] = max(values)
    payload = extract_json_object_from_output(output)
    if payload and payload.get("benchmark") == "native_odbc_async":
        for scenario in payload.get("scenarios", []):
            name = scenario.get("scenario")
            if isinstance(name, str):
                for key, value in scenario.items():
                    if isinstance(value, (int, float)) and not isinstance(value, bool):
                        metrics[f"{name}.{key}"] = float(value)
    else:
        from tool.py.odbc_benchmark_gate import parse_async_benchmark_scenarios
        for scenario in parse_async_benchmark_scenarios(output):
            prefix = f"{scenario.label}.{scenario.encoding}"
            metrics[f"{prefix}.elapsed_ms"] = scenario.duration_ms
            metrics[f"{prefix}.fallbacks"] = float(scenario.fallbacks)
            line = next((strip_shell_log_prefix(line) for line in output.splitlines() if strip_shell_log_prefix(line).startswith(scenario.label + ':')), '')
            for source, target in {'workers': 'workers', 'poolSize': 'pool_size', 'maxInFlight': 'max_in_flight', 'units': 'units', 'routed': 'routed', 'timeouts': 'timeouts'}.items():
                match = re.search(rf'\b{source}=(\d+)', line)
                if match:
                    metrics[f'{prefix}.{target}'] = float(match.group(1))
    return metrics


def parse_odbc_streaming_benchmark_metrics(output: str) -> dict[str, float]:
    metrics: dict[str, float] = {}
    payload = extract_json_object_from_output(output)
    if payload and payload.get("benchmark") == "native_odbc_streaming":
        for scenario in payload.get("scenarios", []):
            label = scenario.get("scenario")
            if isinstance(label, str):
                for key, value in scenario.items():
                    if isinstance(value, (int, float)) and not isinstance(value, bool):
                        metrics[f"{label}.{key}"] = float(value)
        return metrics
    for match in STREAMING_BENCHMARK_RESULT_RE.finditer(output):
        label = match.group("label")
        metrics[f"{label}.elapsed_ms"] = float(match.group("elapsed_ms"))
        metrics[f"{label}.rows"] = float(match.group("rows"))
        metrics[f"{label}.chunks"] = float(match.group("chunks"))
        metrics[f"{label}.rows_per_second"] = float(match.group("rows_per_second"))
        metrics[f"{label}.fetch_size"] = float(match.group("fetch_size"))
        metrics[f"{label}.chunk_size"] = float(match.group("chunk_size"))
    return metrics


def valid_native_benchmark_report(output: str, mode: str) -> bool:
    payload = extract_json_object_from_output(output)
    if not payload or payload.get('benchmark') != f'native_odbc_{mode}' or payload.get('harness_version') != 2:
        return False
    repeats = payload.get('repeats')
    if payload.get('workload') != 'deterministic_8000_rows_v1' or payload.get('rows') != 8000 or payload.get('warmup') != 1 or repeats not in (3, 9):
        return False
    expected = {'streamQueryBuffer', 'streamQueryBatched'} if mode == 'streaming' else {
        'workerCount=1', 'workerCount=4', 'workerCount=4 columnar',
        'workerCount=4 columnar compressed', 'native pool', 'prepared reuse'}
    rows = payload.get('scenarios', [])
    if not isinstance(rows, list) or any(not isinstance(row, dict) for row in rows):
        return False
    if len(rows) != len(expected) or {row.get('scenario') for row in rows} != expected:
        return False
    for row in rows:
        samples = row.get('samples')
        if not isinstance(samples, list) or len(samples) != repeats:
            return False
        for sample in [row, *samples]:
            if not isinstance(sample, dict) or sample.get('rows') != 8000:
                return False
            elapsed = sample.get('elapsed_ms')
            if not isinstance(elapsed, (float, int)) or not math.isfinite(elapsed) or elapsed <= 0:
                return False
            if mode == 'async':
                expected_encoding = 'columnarCompressed' if row['scenario'].endswith('compressed') else ('columnar' if row['scenario'].endswith('columnar') else 'rowMajor')
                if sample.get('timeouts') != 0 or sample.get('fallbacks') != 0 or sample.get('encoding') != expected_encoding or sample.get('actual_encoding') != expected_encoding:
                    return False
            elif not isinstance(sample.get('chunks'), int) or sample['chunks'] <= 0 or sample.get('chunk_size', 0) <= 0 or (row['scenario'] == 'streamQueryBatched' and sample.get('fetch_size', 0) <= 0):
                return False
    return True


def _timing_to_micros(value: str) -> float:
    text = value.strip().lower()
    if text.endswith("ms"):
        return float(text[:-2]) * 1000.0
    if text.endswith("us"):
        return float(text[:-2])
    return float(text) * 1000.0


def incompatible_benchmark_suite_reasons(
    baseline_summary: Mapping[str, Any],
    current_summary: Mapping[str, Any],
) -> dict[str, str]:
    """Return ODBC suites that cannot be compared safely across two runs.

    ODBC timing depends on the package build and workload shape. Legacy
    summaries have no identity metadata, so treating them as a baseline would
    turn environmental drift into a product regression.
    """

    def suites_by_id(summary: Mapping[str, Any]) -> dict[str, Mapping[str, Any]]:
        return {
            str(suite.get("id")): suite
            for suite in summary.get("suites", [])
            if isinstance(suite, Mapping) and isinstance(suite.get("id"), str)
        }

    def comparison_identity(suite: Mapping[str, Any]) -> dict[str, str] | None:
        raw_identity = suite.get("comparison_identity")
        if not isinstance(raw_identity, Mapping):
            return None
        identity = {
            key: value
            for key, value in raw_identity.items()
            if isinstance(key, str) and isinstance(value, str) and value
        }
        return identity or None

    baseline_suites = suites_by_id(baseline_summary)
    current_suites = suites_by_id(current_summary)
    reasons: dict[str, str] = {}
    for suite_id in sorted(set(baseline_suites) & set(current_suites)):
        baseline_identity = comparison_identity(baseline_suites[suite_id])
        current_identity = comparison_identity(current_suites[suite_id])
        if baseline_identity is None or current_identity is None:
            reasons[suite_id] = "missing comparison identity"
        elif baseline_identity != current_identity:
            reasons[suite_id] = "comparison identity differs"
        elif baseline_summary.get("machine") != current_summary.get("machine"):
            reasons[suite_id] = "machine or SDK differs"
    return reasons


def flatten_suite_metrics(
    summary: Mapping[str, Any],
    *,
    excluded_suite_ids: Collection[str] = (),
) -> dict[str, float]:
    flattened: dict[str, float] = {}
    excluded = set(excluded_suite_ids)
    for suite in summary.get("suites", []):
        if not isinstance(suite, dict):
            continue
        suite_id = str(suite.get("id", "unknown"))
        if suite_id in excluded:
            continue
        if suite.get("status", "pass") != "pass":
            continue
        metrics = suite.get("metrics")
        if not isinstance(metrics, dict):
            continue
        for key, value in metrics.items():
            if isinstance(value, bool):
                continue
            if isinstance(value, (int, float)):
                metadata = suite.get("metric_metadata", {}).get(key, metric_metadata(key))
                if metadata.get("category") in {"latency", "throughput", "memory"} and math.isfinite(value):
                    flattened[f"{suite_id}.{key}"] = float(value)
    return flattened


def metric_lower_is_better(metric_key: str) -> bool:
    if metric_metadata(metric_key)['direction'] == 'higher':
        return False
    lower = metric_key.lower()
    if lower.endswith(("_ms", "_us")) or any(
        token in lower for token in ("latency", "duration", "median_us", "p50", "p95", "p99")
    ):
        return True
    if any(
        token in lower
        for token in ("rows_per_sec", "ops_per_sec", "throughput", "ops/s", "rows/s", "speedup")
    ):
        return False
    return True


def metric_metadata(key: str) -> dict[str, str]:
    lower = key.lower()
    if lower == "wall_ms":
        return {"category": "configuration", "unit": "ms", "direction": "none"}
    if lower.endswith(("_us", "_ms")) or "median_us_" in lower:
        return {"category": "latency", "unit": "us" if "_us" in lower else "ms", "direction": "lower"}
    if any(token in lower for token in ("rows_per_sec", "queries_per_sec", "ops_per_sec", "throughput", "speedup")):
        unit = 'ratio' if 'speedup' in lower else ('queries/s' if 'queries_per_sec' in lower else ('rows/s' if 'rows_per_sec' in lower else 'ops/s'))
        return {"category": "throughput", "unit": unit, "direction": "higher"}
    if any(token in lower for token in ("heap_growth", "rss_peak")):
        return {"category": "memory", "unit": "bytes", "direction": "lower"}
    category = "counter" if any(token in lower for token in ("errors", "timeouts", "fallbacks", "chunks", "routed", "completed_requests", "failed_requests")) else "configuration"
    unit = 'bytes' if lower.endswith('_bytes') or 'chunk_size' in lower else ('rows' if lower.endswith('.rows') or lower == 'rows' or 'fetch_size' in lower else 'count')
    return {"category": category, "unit": unit, "direction": "none"}


def write_json(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def approved_controlled_comparison(report: Mapping[str, Any]) -> bool:
    if report.get('status') != 'pass':
        return False
    expected = {(case, mode, signed) for case in ('small_sql_repetitive', 'large_sql_low_compressibility', 'large_incompressible_blob')
                for mode in ('none', 'auto', 'gzip') for signed in (False, True)}
    try:
        for name in ('control', 'forward', 'reverse'):
            section = report[name]
            if section.get('status') != 'pass' or section.get('failures') != [] or section.get('pending_metrics') != [] or section.get('heap_gate_evaluated') is not True:
                return False
            scenarios = section['scenarios']
            if len(scenarios) != len(expected) or {(row['case'], row['compression'], row['signed']) for row in scenarios} != expected:
                return False
            if not math.isfinite(section['throughput_ratio']) or section['throughput_ratio'] < 0.85:
                return False
            pairs = [(section['heap_growth_bytes'], 1.1)] + [(row[field], 1.05) for row in scenarios for field in ('send_p95_us', 'receive_p95_us')]
            for metrics, factor in pairs:
                before, after = metrics['base'], metrics['candidate']
                if any(isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0 for value in (before, after)):
                    return False
                if not math.isclose(metrics['limit'], before * factor) or after > before * factor:
                    return False
    except (KeyError, TypeError, ValueError, AttributeError):
        return False
    return True


def load_summary(path: Path) -> dict[str, Any]:
    summary = json.loads(path.read_text(encoding="utf-8"))
    if summary.get("schema_version", 1) not in (1, 2):
        raise ValueError("Unsupported benchmark summary version")
    return summary


def bootstrap_env(env_path: Path) -> None:
    import_dotenv_if_present(env_path)
    if not os.environ.get("ODBC_TEST_DSN") and os.environ.get("ODBC_DSN"):
        os.environ["ODBC_TEST_DSN"] = os.environ["ODBC_DSN"]


def ensure_on_path() -> None:
    root = str(PROJECT_ROOT)
    if root not in sys.path:
        sys.path.insert(0, root)
