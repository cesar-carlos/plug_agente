from __future__ import annotations

import json
import os
import platform
import re
import subprocess
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Mapping

from tool.py.script_utils import PROJECT_ROOT, get_dsn_driver_family, import_dotenv_if_present

SCHEMA_VERSION = 1
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
    }


def collect_machine_metadata() -> dict[str, str]:
    return {
        "platform": platform.platform(),
        "machine": platform.machine(),
        "processor": platform.processor() or "(unknown)",
        "python_version": platform.python_version(),
    }


def odbc_dsn_configured() -> bool:
    for key in ("ODBC_TEST_DSN", "ODBC_DSN"):
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
                flags[key.lower()] = value
    return flags


def resolve_dart_odbc_fast_root() -> Path | None:
    candidates: list[Path] = []
    env_root = os.environ.get("DART_ODBC_FAST_ROOT", "").strip()
    if env_root:
        candidates.append(Path(env_root))
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


def parse_transport_markdown_metrics(output: str) -> dict[str, float]:
    metrics: dict[str, float] = {}
    for line in output.splitlines():
        if not line.startswith("|") or line.startswith("| ---"):
            continue
        if "case |" in line.lower() or "send p50" in line.lower():
            continue

        parts = [part.strip() for part in line.strip("|").split("|")]
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
    return metrics


def _timing_to_micros(value: str) -> float:
    text = value.strip().lower()
    if text.endswith("ms"):
        return float(text[:-2]) * 1000.0
    if text.endswith("us"):
        return float(text[:-2])
    return float(text) * 1000.0


def flatten_suite_metrics(summary: Mapping[str, Any]) -> dict[str, float]:
    flattened: dict[str, float] = {}
    for suite in summary.get("suites", []):
        if not isinstance(suite, dict):
            continue
        suite_id = str(suite.get("id", "unknown"))
        metrics = suite.get("metrics")
        if not isinstance(metrics, dict):
            continue
        for key, value in metrics.items():
            if isinstance(value, bool):
                continue
            if isinstance(value, (int, float)):
                flattened[f"{suite_id}.{key}"] = float(value)
    return flattened


def metric_lower_is_better(metric_key: str) -> bool:
    lower = metric_key.lower()
    if any(token in lower for token in ("rows_per_sec", "ops_per_sec", "throughput", "ops/s", "rows/s")):
        return False
    if any(
        token in lower
        for token in ("_ms", "_us", "_s", "wall_ms", "latency", "duration", "p50", "p95", "p99")
    ):
        return True
    return True


def write_json(path: Path, payload: Mapping[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def load_summary(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def bootstrap_env(env_path: Path) -> None:
    import_dotenv_if_present(env_path)
    if not os.environ.get("ODBC_TEST_DSN") and os.environ.get("ODBC_DSN"):
        os.environ["ODBC_TEST_DSN"] = os.environ["ODBC_DSN"]


def ensure_on_path() -> None:
    root = str(PROJECT_ROOT)
    if root not in sys.path:
        sys.path.insert(0, root)
