from __future__ import annotations

import re
from datetime import datetime
from pathlib import Path
from typing import Any, Mapping

from tool.py.benchmark_common import SCHEMA_VERSION, SAFE_ENV_KEYS, write_json

_LEGACY_STATUS_MAP = {
    "pass": "pass",
    "partial_fail": "fail",
    "fail": "fail",
    "fail_on_sql_server_run": "fail",
    "skipped": "skipped",
    "error": "error",
}

_SECRET_KEY_RE = re.compile(
    r"(url|token|secret|password|dsn|jwt|credential|connection_string)",
    re.IGNORECASE,
)
_URL_RE = re.compile(r"https?://", re.IGNORECASE)

_METRIC_KEYS = frozenset(
    {
        "wall_ms",
        "wall_s",
        "insert_ms",
        "update_ms",
        "delete_ms",
        "total_ms",
        "queued_elapsed_ms",
        "create_ms",
        "drop_ms",
        "insert_rows_per_sec",
        "update_rows_per_sec",
        "delete_rows_per_sec",
        "passed",
        "failed",
        "skipped",
        "cases",
        "rows",
        "concurrency",
        "bulk_insert_parallel_total",
        "bulk_insert_chunked_total",
    }
)


def _run_timestamp_to_iso(run_timestamp: str) -> str:
    try:
        parsed = datetime.strptime(run_timestamp, "%Y%m%d_%H%M%S")
        return parsed.isoformat(timespec="seconds")
    except ValueError:
        return run_timestamp


def _sanitize_config(config: Mapping[str, Any] | None) -> dict[str, Any]:
    if not config:
        return {}

    safe_lower = {key.lower() for key in SAFE_ENV_KEYS}
    flags: dict[str, Any] = {}
    for key, raw in config.items():
        key_text = str(key)
        if _SECRET_KEY_RE.search(key_text) or _URL_RE.search(str(raw)):
            continue
        normalized = key_text.lower()
        if normalized not in safe_lower and normalized not in {
            "odbc_e2e_dml_stress_tests",
            "odbc_e2e_dml_bulk_tests",
            "odbc_e2e_codcliente_tests",
            "odbc_e2e_transactional_batch",
            "odbc_e2e_dml_bulk_chunk_size",
            "method",
        }:
            continue
        value = raw
        if isinstance(value, str):
            text = value.strip()
            if text.lower() in {"true", "false"}:
                flags[normalized] = text.lower() == "true"
                continue
            if _URL_RE.search(text):
                continue
            try:
                flags[normalized] = int(text) if "." not in text else float(text)
                continue
            except ValueError:
                if text and len(text) < 64:
                    flags[normalized] = text
                continue
        if isinstance(value, bool):
            flags[normalized] = value
        elif isinstance(value, (int, float)):
            flags[normalized] = value
    flags.setdefault("odbc_test_dsn_configured", True)
    return flags


def _extract_metrics(entry: Mapping[str, Any]) -> dict[str, float]:
    metrics: dict[str, float] = {}
    for key, value in entry.items():
        if key in _METRIC_KEYS and isinstance(value, (int, float)):
            metric_key = key
            metric_value = float(value)
            if key == "wall_s":
                metric_key = "wall_ms"
                metric_value *= 1000.0
            metrics[metric_key] = metric_value
    return metrics


def _suite_from_result(entry: Mapping[str, Any]) -> dict[str, Any]:
    test = str(entry.get("test", "unknown"))
    driver = str(entry.get("driver", "unknown"))
    status = _LEGACY_STATUS_MAP.get(str(entry.get("status", "error")), "error")
    suite: dict[str, Any] = {
        "id": f"{test}.{driver}",
        "kind": "flutter_test",
        "status": status,
    }
    metrics = _extract_metrics(entry)
    if metrics:
        suite["metrics"] = metrics
    if "wall_ms" in metrics:
        suite["wall_ms"] = metrics["wall_ms"]
    elif "wall_s" in entry and isinstance(entry["wall_s"], (int, float)):
        suite["wall_ms"] = float(entry["wall_s"]) * 1000.0
    reason = entry.get("reason") or entry.get("note")
    if reason and status in {"skipped", "fail", "error"}:
        suite["reason"] = str(reason)[:500]
    return suite


def _suite_from_suite_result(suite_id: str, entry: Mapping[str, Any]) -> dict[str, Any]:
    status = _LEGACY_STATUS_MAP.get(str(entry.get("status", "error")), "error")
    suite: dict[str, Any] = {
        "id": suite_id,
        "kind": "flutter_test",
        "status": status,
    }
    metrics = _extract_metrics(entry)
    if metrics:
        suite["metrics"] = metrics
    if "wall_ms" in metrics:
        suite["wall_ms"] = metrics["wall_ms"]
    log_file = entry.get("log")
    if isinstance(log_file, str) and log_file:
        suite["log_file"] = log_file
    failures = entry.get("failures")
    if failures:
        suite["reason"] = "; ".join(str(item) for item in failures)[:500]
    return suite


def migrate_legacy_summary(legacy: Mapping[str, Any], *, source_path: Path | None = None) -> dict[str, Any]:
    run_id = str(legacy.get("run_timestamp") or legacy.get("run_id") or "unknown")
    suites: list[dict[str, Any]] = []

    for entry in legacy.get("results", []):
        if isinstance(entry, dict):
            suites.append(_suite_from_result(entry))

    suite_results = legacy.get("suite_results")
    if isinstance(suite_results, dict):
        for suite_id, entry in suite_results.items():
            if suite_id == "totals" or not isinstance(entry, dict):
                continue
            suites.append(_suite_from_suite_result(str(suite_id), entry))

    notes = [
        "Migrated from legacy benchmark_logs/ E2E summary (schema v1).",
        "Connection strings, URLs, tokens and host-specific config were stripped.",
    ]
    if legacy.get("scope"):
        notes.append(f"Legacy scope: {legacy['scope']}")
    if source_path is not None:
        notes.append(f"Source: {source_path.as_posix()}")

    return {
        "$schema": "../schema/summary.schema.json",
        "schema_version": SCHEMA_VERSION,
        "run_id": run_id,
        "captured_at": _run_timestamp_to_iso(run_id),
        "git": {
            "commit_sha": "migrated-legacy",
            "branch": "migrated-legacy",
            "dirty": False,
        },
        "machine": {
            "platform": "legacy-e2e",
            "machine": "migrated",
            "processor": "benchmark_logs-import",
        },
        "env_flags": _sanitize_config(legacy.get("config") if isinstance(legacy.get("config"), dict) else None),
        "suites": suites,
        "notes": notes,
    }


def migrate_legacy_file(source: Path, output_dir: Path) -> Path:
    import json

    legacy = json.loads(source.read_text(encoding="utf-8"))
    summary = migrate_legacy_summary(legacy, source_path=source)
    destination = output_dir / summary["run_id"] / "summary.json"
    write_json(destination, summary)
    return destination
