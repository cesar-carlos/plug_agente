#!/usr/bin/env python3
"""
Plug Agente benchmark suite runner.

Canonical layout:
  benchmarks/baseline/summary.json   committed baseline (schema v1)
  benchmarks/results/<run_id>/       ephemeral per-run outputs (gitignored)
    summary.json
    REPORT.md
    *.log
  benchmarks/history/<run_id>/     versioned samples (migrated or promoted)

Legacy ad-hoc folders (benchmark_logs/, build/perf_reports/) are not used by this tool.
Migrate legacy logs with: python tool/benchmarks/migrate_benchmark_logs.py
Promote a good run to baseline: python tool/benchmarks/promote_benchmark_baseline.py
Compare runs over time: python tool/benchmarks/benchmark_evolution_report.py --include-history

dart run vs flutter test (FFI / isolates)
-----------------------------------------
transport_pipeline_json runs `dart run tool/benchmarks/benchmark_transport_pipeline.dart --path async`.
The async codec path depends on dart:ui isolate offload. Under plain `dart run`, the
conditional import falls back to a stub without real FFI/isolate behavior, so numbers
are not comparable to production or CI.

Prefer the flutter_test suite for regression gates and baselines:
  flutter test test/infrastructure/codecs/transport_pipeline_benchmark_test.dart --tags perf
  python tool/benchmarks/run_benchmark_suite.py --only transport_pipeline

Use --skip-dart-tool (or omit transport_pipeline_json via --only) in CI and when ODBC
is unavailable. Sync-path micro-benchmarks via `dart run ... --path sync` remain valid
for local quick checks only.

Optional gate env (when ODBC DSN is configured):
  BENCHMARK_COLUMNAR_MIN_SPEEDUP=1.30  # async: workerCount=4 columnar vs rowMajor wall time
  BENCHMARK_STREAMING_MIN_SPEEDUP=2.0  # streaming: streamQueryBatched vs streamQuery rows/s
  BENCHMARK_GATEWAY_ENCODING=1         # include tool/benchmarks/benchmark_odbc_gateway_encoding.dart in suite
"""

from __future__ import annotations


import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parents[1]
_ROOT = _TOOL_DIR.parent
for _entry in (str(_ROOT), str(_TOOL_DIR)):
    if _entry not in sys.path:
        sys.path.insert(0, _entry)

import argparse
import json
import os
import sys
import time
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.py.benchmark_common import (
    BASELINE_PATH,
    RESULTS_DIR,
    SCHEMA_PATH,
    SCHEMA_VERSION,
    bootstrap_env,
    captured_at_now,
    collect_env_flags,
    collect_git_metadata,
    collect_machine_metadata,
    ensure_on_path,
    odbc_dsn_configured,
    parse_transport_json_metrics,
    parse_transport_markdown_metrics,
    resolve_dart_odbc_fast_root,
    run_id_now,
    write_json,
)
from tool.py.odbc_benchmark_runner import run_odbc_async_benchmark, run_odbc_streaming_benchmark
from tool.py.script_utils import PROJECT_ROOT, resolve_env_path, run_streaming

TRANSPORT_TEST = "test/infrastructure/codecs/transport_pipeline_benchmark_test.dart"
TRANSPORT_DART_TOOL = "tool/benchmarks/benchmark_transport_pipeline.dart"
GATEWAY_ENCODING_TOOL = "tool/benchmarks/benchmark_odbc_gateway_encoding.dart"


def filter_suite_plans(
    plans: list[dict[str, Any]],
    *,
    only: set[str] | None,
    skip_dart_tool: bool,
) -> list[dict[str, Any]]:
    filtered: list[dict[str, Any]] = []
    for plan in plans:
        suite_id = plan["id"]
        if only is not None and suite_id not in only:
            continue
        if skip_dart_tool and suite_id == "transport_pipeline_json":
            continue
        filtered.append(plan)
    return filtered


def build_suite_plans() -> list[dict[str, Any]]:
    plans: list[dict[str, Any]] = [
        {
            "id": "transport_pipeline",
            "kind": "flutter_test",
            "enabled": True,
            "command": [
                "flutter",
                "test",
                TRANSPORT_TEST,
                "--tags",
                "perf",
            ],
            "cwd": PROJECT_ROOT,
        },
        {
            "id": "transport_pipeline_json",
            "kind": "dart_tool",
            "enabled": True,
            "command": [
                "dart",
                "run",
                TRANSPORT_DART_TOOL,
                "--json",
                "--path",
                "async",
                "--iterations",
                "4",
            ],
            "cwd": PROJECT_ROOT,
        },
    ]

    if odbc_dsn_configured():
        odbc_root = resolve_dart_odbc_fast_root()
        if odbc_root is None:
            plans.extend(
                [
                    {
                        "id": "odbc_async",
                        "kind": "dart_odbc_fast",
                        "enabled": False,
                        "skip_reason": "DART_ODBC_FAST_ROOT not found (set env or clone dart_odbc_fast)",
                    },
                    {
                        "id": "odbc_streaming",
                        "kind": "dart_odbc_fast",
                        "enabled": False,
                        "skip_reason": "DART_ODBC_FAST_ROOT not found (set env or clone dart_odbc_fast)",
                    },
                ]
            )
        else:
            plans.extend(
                [
                    {
                        "id": "odbc_async",
                        "kind": "dart_odbc_fast",
                        "enabled": True,
                        "package_root": str(odbc_root),
                    },
                    {
                        "id": "odbc_streaming",
                        "kind": "dart_odbc_fast",
                        "enabled": True,
                        "package_root": str(odbc_root),
                    },
                ]
            )
        if os.environ.get("BENCHMARK_GATEWAY_ENCODING", "").strip().lower() in {"1", "true", "yes"}:
            plans.append(
                {
                    "id": "odbc_gateway_encoding",
                    "kind": "dart_tool",
                    "enabled": True,
                    "command": [
                        "dart",
                        "run",
                        GATEWAY_ENCODING_TOOL,
                        "--json",
                    ],
                    "cwd": PROJECT_ROOT,
                }
            )
    else:
        reason = "ODBC_TEST_DSN / ODBC_DSN not configured in .env"
        plans.extend(
            [
                {
                    "id": "odbc_async",
                    "kind": "dart_odbc_fast",
                    "enabled": False,
                    "skip_reason": reason,
                },
                {
                    "id": "odbc_streaming",
                    "kind": "dart_odbc_fast",
                    "enabled": False,
                    "skip_reason": reason,
                },
            ]
        )
    return plans


def print_dry_run(plans: list[dict[str, Any]]) -> None:
    print("Benchmark suite dry-run")
    print(f"Project root: {PROJECT_ROOT}")
    print(f"Baseline: {BASELINE_PATH}")
    print(f"Schema: {SCHEMA_PATH}")
    print()
    for plan in plans:
        status = "would run" if plan.get("enabled") else "skip"
        print(f"- [{status}] {plan['id']} ({plan['kind']})")
        if plan.get("enabled") and plan.get("command"):
            print(f"    command: {' '.join(plan['command'])}")
        if plan.get("enabled") and plan.get("package_root"):
            print(f"    package_root: {plan['package_root']}")
        if not plan.get("enabled"):
            print(f"    reason: {plan.get('skip_reason', 'disabled')}")


def run_gateway_encoding_tool(log_path: Path) -> dict[str, Any]:
    started = time.perf_counter()
    exit_code = run_streaming(
        ["dart", "run", GATEWAY_ENCODING_TOOL, "--json"],
        cwd=PROJECT_ROOT,
        log_path=log_path,
    )
    wall_ms = (time.perf_counter() - started) * 1000.0
    output = log_path.read_text(encoding="utf-8") if log_path.is_file() else ""
    metrics: dict[str, float] = {}
    status = "pass" if exit_code == 0 else "error"
    if exit_code == 0:
        try:
            payload = json.loads(output)
            for scenario in payload.get("scenarios", []):
                name = scenario.get("scenario")
                median = scenario.get("median_us")
                if isinstance(name, str) and isinstance(median, (int, float)):
                    metrics[f"median_us_{name}"] = float(median)
        except json.JSONDecodeError:
            status = "error"
    return {
        "id": "odbc_gateway_encoding",
        "kind": "dart_tool",
        "status": status,
        "wall_ms": round(wall_ms, 2),
        "exit_code": exit_code,
        "log_file": log_path.name,
        "metrics": metrics,
    }


def enforce_columnar_speedup_gate(suites: list[dict[str, Any]]) -> int:
    raw = os.environ.get("BENCHMARK_COLUMNAR_MIN_SPEEDUP", "").strip()
    if not raw:
        return 0
    try:
        min_speedup = float(raw)
    except ValueError:
        print(f"Invalid BENCHMARK_COLUMNAR_MIN_SPEEDUP: {raw}", file=sys.stderr)
        return 2
    gateway = next((suite for suite in suites if suite.get("id") == "odbc_gateway_encoding"), None)
    if gateway is None or gateway.get("status") != "pass":
        return 0
    metrics = gateway.get("metrics") or {}
    balanced = metrics.get("median_us_balancedServer_rowMajor")
    columnar = metrics.get("median_us_highThroughput_columnar")
    if not isinstance(balanced, (int, float)) or not isinstance(columnar, (int, float)) or columnar <= 0:
        return 0
    speedup = balanced / columnar
    if speedup < min_speedup:
        print(
            f"Columnar speedup gate failed: {speedup:.3f} < {min_speedup} "
            f"(balanced={balanced}us columnar={columnar}us)",
            file=sys.stderr,
        )
        return 3
    return 0


def run_transport_flutter_test(log_path: Path) -> dict[str, Any]:
    started = time.perf_counter()
    exit_code = run_streaming(
        ["flutter", "test", TRANSPORT_TEST, "--tags", "perf"],
        cwd=PROJECT_ROOT,
        log_path=log_path,
    )
    wall_ms = (time.perf_counter() - started) * 1000.0
    output = log_path.read_text(encoding="utf-8") if log_path.is_file() else ""
    metrics = parse_transport_markdown_metrics(output)
    status = "pass" if exit_code == 0 else "fail"
    return {
        "id": "transport_pipeline",
        "kind": "flutter_test",
        "status": status,
        "wall_ms": round(wall_ms, 2),
        "exit_code": exit_code,
        "log_file": log_path.name,
        "metrics": metrics,
    }


def run_transport_json_tool(log_path: Path) -> dict[str, Any]:
    started = time.perf_counter()
    exit_code = run_streaming(
        [
            "dart",
            "run",
            TRANSPORT_DART_TOOL,
            "--json",
            "--path",
            "async",
            "--iterations",
            "4",
        ],
        cwd=PROJECT_ROOT,
        log_path=log_path,
    )
    wall_ms = (time.perf_counter() - started) * 1000.0
    output = log_path.read_text(encoding="utf-8") if log_path.is_file() else ""
    metrics: dict[str, float] = {}
    if exit_code == 0:
        try:
            payload = json.loads(output)
            metrics = parse_transport_json_metrics(payload)
        except json.JSONDecodeError:
            pass
    status = "pass" if exit_code == 0 else "error"
    return {
        "id": "transport_pipeline_json",
        "kind": "dart_tool",
        "status": status,
        "wall_ms": round(wall_ms, 2),
        "exit_code": exit_code,
        "log_file": log_path.name,
        "metrics": metrics,
    }


def run_odbc_suite(suite_id: str, package_root: Path, log_path: Path) -> dict[str, Any]:
    runner = run_odbc_async_benchmark if suite_id == "odbc_async" else run_odbc_streaming_benchmark
    exit_code, metrics, _output = runner(package_root=package_root, log_path=log_path)
    status = "pass" if exit_code == 0 else "fail"
    return {
        "id": suite_id,
        "kind": "dart_odbc_fast",
        "status": status,
        "wall_ms": round(metrics.get("wall_ms", 0.0), 2),
        "exit_code": exit_code,
        "log_file": log_path.name,
        "metrics": metrics,
    }


def skipped_suite(suite_id: str, kind: str, reason: str) -> dict[str, Any]:
    return {
        "id": suite_id,
        "kind": kind,
        "status": "skipped",
        "reason": reason,
    }


def render_report(summary: dict[str, Any]) -> str:
    lines = [
        "# Relatório de benchmark — plug_agente",
        "",
        f"- Run ID: `{summary['run_id']}`",
        f"- Capturado em: {summary['captured_at']}",
        f"- Commit: `{summary['git']['commit_sha']}` ({summary['git']['branch']})",
        f"- Working tree dirty: {summary['git']['dirty']}",
        f"- Plataforma: {summary['machine']['platform']}",
        "",
        "## Suites",
        "",
    ]
    for suite in summary["suites"]:
        lines.append(f"### {suite['id']}")
        lines.append(f"- Status: **{suite['status']}**")
        if "wall_ms" in suite:
            lines.append(f"- Wall time: {suite['wall_ms']:.2f} ms")
        if suite.get("reason"):
            lines.append(f"- Motivo: {suite['reason']}")
        if suite.get("log_file"):
            lines.append(f"- Log: `{suite['log_file']}`")
        metrics = suite.get("metrics") or {}
        if metrics:
            lines.append("- Métricas:")
            for key in sorted(metrics):
                lines.append(f"  - `{key}`: {metrics[key]}")
        lines.append("")
    lines.extend(
        [
            "## Comparação com baseline",
            "",
            "```bash",
            "python tool/benchmarks/compare_benchmark_summary.py \\",
            f"  --baseline benchmarks/baseline/summary.json \\",
            f"  --current benchmarks/results/{summary['run_id']}/summary.json",
            "```",
            "",
        ]
    )
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ensure_on_path()
    parser = argparse.ArgumentParser(description="Run plug_agente benchmark suite.")
    parser.add_argument("--dry-run", action="store_true", help="List planned benchmarks and exit.")
    parser.add_argument("--env-path", default=".env", help="Path to .env for ODBC flags (default: .env)")
    parser.add_argument(
        "--output-dir",
        default="",
        help="Override output directory (default: benchmarks/results/<run_id>/)",
    )
    parser.add_argument(
        "--only",
        default="",
        help="Comma-separated suite ids to run (default: all enabled suites)",
    )
    parser.add_argument(
        "--skip-dart-tool",
        action="store_true",
        help="Skip transport_pipeline_json (dart run async stub; prefer flutter_test in CI)",
    )
    parser.add_argument(
        "--compare-baseline",
        action="store_true",
        help="After the run, compare summary against benchmarks/baseline/summary.json",
    )
    parser.add_argument(
        "--compare-threshold",
        type=float,
        default=0.20,
        help="Regression threshold for --compare-baseline (default: 0.20)",
    )
    args = parser.parse_args(argv)

    bootstrap_env(resolve_env_path(args.env_path))
    only = {item.strip() for item in args.only.split(",") if item.strip()} or None
    plans = filter_suite_plans(
        build_suite_plans(),
        only=only,
        skip_dart_tool=args.skip_dart_tool,
    )
    if args.dry_run:
        print_dry_run(plans)
        return 0

    run_id = run_id_now()
    output_dir = Path(args.output_dir) if args.output_dir else RESULTS_DIR / run_id
    output_dir.mkdir(parents=True, exist_ok=True)

    suites: list[dict[str, Any]] = []
    had_failure = False
    for plan in plans:
        suite_id = plan["id"]
        if not plan.get("enabled"):
            suites.append(skipped_suite(suite_id, plan["kind"], plan.get("skip_reason", "disabled")))
            continue

        log_path = output_dir / f"{suite_id}.log"
        if suite_id == "transport_pipeline":
            suite = run_transport_flutter_test(log_path)
        elif suite_id == "transport_pipeline_json":
            suite = run_transport_json_tool(log_path)
        elif suite_id == "odbc_gateway_encoding":
            suite = run_gateway_encoding_tool(log_path)
        elif plan["kind"] == "dart_odbc_fast":
            suite = run_odbc_suite(suite_id, Path(plan["package_root"]), log_path)
        else:
            suite = skipped_suite(suite_id, plan["kind"], "unsupported plan")
        suites.append(suite)
        if suite["status"] in {"fail", "error"}:
            had_failure = True

    summary: dict[str, Any] = {
        "$schema": "../schema/summary.schema.json",
        "schema_version": SCHEMA_VERSION,
        "run_id": run_id,
        "captured_at": captured_at_now(),
        "git": collect_git_metadata(),
        "machine": collect_machine_metadata(),
        "env_flags": collect_env_flags(),
        "suites": suites,
        "notes": [
            "Ephemeral run output; compare against benchmarks/baseline/summary.json.",
            "Legacy benchmark_logs/ format is not schema-compatible with this summary.",
        ],
    }

    summary_path = output_dir / "summary.json"
    report_path = output_dir / "REPORT.md"
    write_json(summary_path, summary)
    report_path.write_text(render_report(summary), encoding="utf-8")

    print()
    print(f"Benchmark run complete: {output_dir}")
    print(f"  summary: {summary_path}")
    print(f"  report:  {report_path}")

    compare_exit = 0
    if args.compare_baseline:
        from tool.benchmarks.compare_benchmark_summary import main as compare_main

        compare_exit = compare_main(
            [
                "--baseline",
                str(BASELINE_PATH),
                "--current",
                str(summary_path),
                "--threshold",
                str(args.compare_threshold),
            ]
        )

    columnar_gate_exit = enforce_columnar_speedup_gate(suites)
    if columnar_gate_exit != 0:
        return columnar_gate_exit

    if compare_exit != 0:
        return compare_exit
    return 1 if had_failure else 0


if __name__ == "__main__":
    raise SystemExit(main())
