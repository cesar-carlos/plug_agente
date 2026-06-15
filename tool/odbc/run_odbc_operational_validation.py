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
from datetime import datetime
from pathlib import Path

from py.script_utils import (
    Console,
    PROJECT_ROOT,
    TOOL_DIR,
    format_timestamp,
    get_driver_tuning_recommendation,
    get_dsn_driver_family,
    get_effective_env_value,
    get_git_commit_or_default,
    get_native_adaptive_eligibility,
    import_dotenv_if_present,
    invoke_step,
    resolve_env_path,
    run_streaming,
    update_context_from_health_snapshot_template,
)


def build_validation_report(context: dict[str, str], steps: dict[str, dict[str, str]]) -> str:
    step_labels = {
        "OdbcRuntime": "ODBC runtime",
        "Preflight": "Preflight",
        "Smoke": "Smoke",
        "Burst": "Burst",
        "Benchmark": "Benchmark",
        "StreamingBenchmark": "Streaming benchmark",
        "DriverMatrixBenchmark": "Driver matrix benchmark",
    }
    report_lines = [
        "# ODBC Operational Validation Report",
        "",
        f"Generated at: {context['GeneratedAt']}",
        "",
        "## Environment",
        "",
        "| Field | Value |",
        "| --- | --- |",
        f"| Operator | {context['Operator']} |",
        f"| Host | {context['Host']} |",
        f"| Repo root | `{context['RepoRoot']}` |",
        f"| Run directory | `{context['RunDirectory']}` |",
        f"| Build / commit | `{context['Commit']}` |",
        f"| DSN used | `{context['DsnUsed']}` |",
        f"| Driver family | {context['DriverFamily']} |",
        f"| Native/adaptive pool eligibility | {context['NativeAdaptiveEligibility']} |",
        f"| Smoke query | `{context['SmokeQuery']}` |",
        f"| Long query | `{context['LongQuery']}` |",
        "",
        "## Effective Tuning",
        "",
        "```env",
        f"ODBC_POOL_SIZE={context['OdbcPoolSize']}",
        f"ODBC_ASYNC_WORKER_COUNT={context['OdbcAsyncWorkerCount']}",
        f"ODBC_ASYNC_MAX_PENDING_REQUESTS={context['OdbcAsyncMaxPendingRequests']}",
        f"ODBC_RESULT_ENCODING={context['OdbcResultEncoding']}",
        f"SQL_QUEUE_MAX_SIZE={context['SqlQueueMaxSize']}",
        f"SQL_QUEUE_MAX_WORKERS={context['SqlQueueMaxWorkers']}",
        f"SQL_QUEUE_TIMEOUT_SEC={context['SqlQueueTimeoutSec']}",
        f"ODBC_POOL_ACQUIRE_TIMEOUT_SEC={context['PoolAcquireTimeoutSec']}",
        f"CIRCUIT_BREAKER_FAILURE_THRESHOLD={context['CircuitBreakerFailureThreshold']}",
        f"CIRCUIT_BREAKER_RESET_SEC={context['CircuitBreakerResetSec']}",
        f"RUN_ODBC_BURST_TESTS={context['RunOdbcBurstTests']}",
        "```",
        "",
        "Driver recommendation:",
        "",
        f"> {context['DriverTuningRecommendation']}",
        "",
        "## Step Status",
        "",
        "| Step | Status | Command |",
        "| --- | --- | --- |",
    ]
    for key, label in step_labels.items():
        step = steps[key]
        report_lines.append(f"| {label} | {step['Status']} | `{step['Command']}` |")

    report_lines.extend(
        [
            "",
            "## Step Artifacts",
            "",
            "| Step | Log | Started at | Finished at |",
            "| --- | --- | --- | --- |",
        ]
    )
    for key, label in step_labels.items():
        step = steps[key]
        report_lines.append(
            f"| {label} | {step['Log']} | {step['StartedAt']} | {step['FinishedAt']} |"
        )

    report_lines.extend(
        [
            "",
            "## Auxiliary Artifacts",
            "",
            "| Artifact | Purpose |",
            "| --- | --- |",
            "| `health_snapshot_template.json` | Template no shape atual de `agent.getHealth` com tuning efetivo do ambiente local. |",
            "| `odbc_runtime.log` | Smoke sem DSN para inicializacao do `odbc_fast`, worker async e exports columnar/compressed. |",
            "| `health_burst_*_before.json` / `health_burst_*_after.json` | Snapshots reais de `HealthService.getHealthStatusAsync()` gravados pelo teste de burst quando burst/all roda. |",
            "| `driver_matrix_*_async.log` / `driver_matrix_*_streaming.log` | Benchmark por driver configurado; drivers sem DSN sao pulados. |",
            "",
            "## Automated Health Snapshots",
            "",
            "When Burst runs, `sql_queue_burst_test.dart` receives `ODBC_BURST_HEALTH_SNAPSHOT_DIR` and writes before/after health JSON files into the run directory. If the Burst step is not requested, collect `agent.getHealth` manually before making tuning decisions.",
            "",
            "## Quick Comparison",
            "",
            "| Field | Before | After | Notes |",
            "| --- | --- | --- | --- |",
            "| `odbc_runtime_tuning.async_worker_count` | | | |",
            "| `odbc_runtime_tuning.async_max_pending_requests` | | | |",
            "| `pool.active_count` | | | |",
            "| `pool.fallbacks_total` | | | |",
            "| `sql_queue.rejections_total` | | | |",
            "| `sql_queue.timeouts_total` | | | |",
            "| `sql_queue.p95_wait_time_ms` | | | |",
            "| `queries.p95_latency_ms` | | | |",
            "| `queries.p99_latency_ms` | | | |",
            "| `timeouts.pool_total` | | | |",
            "",
            "## Notes",
            "",
            "- Tuning decision:",
            "- Risks observed:",
            "- Follow-up:",
            "",
        ]
    )
    return "\n".join(report_lines)


def main() -> int:
    parser = argparse.ArgumentParser(description="Run ODBC operational validation and write a worksheet.")
    parser.add_argument("--run-smoke", action="store_true")
    parser.add_argument("--run-burst", action="store_true")
    parser.add_argument("--run-benchmark", action="store_true")
    parser.add_argument("--run-streaming-benchmark", action="store_true")
    parser.add_argument("--run-driver-matrix-benchmark", action="store_true")
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--skip-preflight", action="store_true")
    parser.add_argument("--env-path", default=".env")
    parser.add_argument("--output-path", default="")
    args = parser.parse_args()

    if args.all:
        args.run_smoke = True
        args.run_burst = True
        args.run_benchmark = True
        args.run_streaming_benchmark = True
        args.run_driver_matrix_benchmark = True

    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    run_directory = PROJECT_ROOT / "artifacts" / "odbc_validation" / timestamp
    resolved_env_path = resolve_env_path(args.env_path)
    import_dotenv_if_present(resolved_env_path)

    context: dict[str, str] = {
        "GeneratedAt": format_timestamp(),
        "Operator": os.environ.get("USERNAME") or os.environ.get("USER") or "(unknown)",
        "Host": os.environ.get("COMPUTERNAME") or os.environ.get("HOSTNAME") or "(unknown)",
        "RepoRoot": str(PROJECT_ROOT),
        "RunDirectory": str(run_directory),
        "Commit": get_git_commit_or_default(),
        "DsnUsed": get_effective_env_value(
            (
                "ODBC_E2E_RPC_DSN",
                "ODBC_TEST_DSN",
                "ODBC_DSN",
                "ODBC_TEST_DSN_SQL_SERVER",
                "ODBC_DSN_SQL_SERVER",
                "ODBC_TEST_DSN_POSTGRESQL",
                "ODBC_DSN_POSTGRESQL",
            )
        ),
        "SmokeQuery": get_effective_env_value(("ODBC_INTEGRATION_SMOKE_QUERY",)),
        "LongQuery": get_effective_env_value(
            (
                "ODBC_INTEGRATION_LONG_QUERY",
                "ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE",
                "ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER",
                "ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL",
            )
        ),
        "OdbcPoolSize": get_effective_env_value(("ODBC_POOL_SIZE",)),
        "OdbcAsyncWorkerCount": get_effective_env_value(("ODBC_ASYNC_WORKER_COUNT",)),
        "OdbcAsyncMaxPendingRequests": get_effective_env_value(
            ("ODBC_ASYNC_MAX_PENDING_REQUESTS",)
        ),
        "OdbcResultEncoding": get_effective_env_value(("ODBC_RESULT_ENCODING",)),
        "SqlQueueMaxSize": get_effective_env_value(("SQL_QUEUE_MAX_SIZE",)),
        "SqlQueueMaxWorkers": get_effective_env_value(("SQL_QUEUE_MAX_WORKERS",)),
        "SqlQueueTimeoutSec": get_effective_env_value(("SQL_QUEUE_TIMEOUT_SEC",)),
        "PoolAcquireTimeoutSec": get_effective_env_value(("ODBC_POOL_ACQUIRE_TIMEOUT_SEC",)),
        "CircuitBreakerFailureThreshold": get_effective_env_value(
            ("CIRCUIT_BREAKER_FAILURE_THRESHOLD",)
        ),
        "CircuitBreakerResetSec": get_effective_env_value(("CIRCUIT_BREAKER_RESET_SEC",)),
        "RunOdbcBurstTests": get_effective_env_value(("RUN_ODBC_BURST_TESTS",)),
    }

    if not context["SmokeQuery"]:
        context["SmokeQuery"] = "SELECT 1"
    if not context["DsnUsed"]:
        context["DsnUsed"] = "(not configured)"
    context["DriverFamily"] = get_dsn_driver_family(context["DsnUsed"])
    context["NativeAdaptiveEligibility"] = get_native_adaptive_eligibility(context["DriverFamily"])
    context["DriverTuningRecommendation"] = get_driver_tuning_recommendation(context["DriverFamily"])
    if not context["LongQuery"]:
        context["LongQuery"] = "(not configured)"
    if not context["CircuitBreakerFailureThreshold"]:
        context["CircuitBreakerFailureThreshold"] = "5"
    if not context["CircuitBreakerResetSec"]:
        context["CircuitBreakerResetSec"] = "30"
    if not context["OdbcResultEncoding"]:
        context["OdbcResultEncoding"] = "rowMajor"

    steps: dict[str, dict[str, str]] = {
        "OdbcRuntime": {
            "Status": "pending",
            "Command": "flutter test test/tool/odbc_fast_runtime_check_test.dart",
            "Log": "odbc_runtime.log",
            "StartedAt": "-",
            "FinishedAt": "-",
        },
        "Preflight": {
            "Status": "skipped" if args.skip_preflight else "pending",
            "Command": "dart run tool/e2e/check_e2e_env.dart",
            "Log": "(not requested)" if args.skip_preflight else "preflight.log",
            "StartedAt": "-",
            "FinishedAt": "-",
        },
        "Smoke": {
            "Status": "pending" if args.run_smoke else "not requested",
            "Command": "flutter test test/integration/odbc_queued_gateway_smoke_live_e2e_test.dart",
            "Log": "smoke.log" if args.run_smoke else "(not requested)",
            "StartedAt": "-",
            "FinishedAt": "-",
        },
        "Burst": {
            "Status": "pending" if args.run_burst else "not requested",
            "Command": "flutter test test/integration/sql_queue_burst_test.dart",
            "Log": "burst.log" if args.run_burst else "(not requested)",
            "StartedAt": "-",
            "FinishedAt": "-",
        },
        "Benchmark": {
            "Status": "pending" if args.run_benchmark else "not requested",
            "Command": "python tool/benchmarks/odbc_async_benchmark.py",
            "Log": "benchmark.log" if args.run_benchmark else "(not requested)",
            "StartedAt": "-",
            "FinishedAt": "-",
        },
        "StreamingBenchmark": {
            "Status": "pending" if args.run_streaming_benchmark else "not requested",
            "Command": "python tool/benchmarks/odbc_streaming_benchmark.py",
            "Log": "streaming_benchmark.log" if args.run_streaming_benchmark else "(not requested)",
            "StartedAt": "-",
            "FinishedAt": "-",
        },
        "DriverMatrixBenchmark": {
            "Status": "pending" if args.run_driver_matrix_benchmark else "not requested",
            "Command": "python tool/benchmarks/odbc_driver_matrix_benchmark.py --output-directory <runDirectory>",
            "Log": "driver_matrix.log" if args.run_driver_matrix_benchmark else "(not requested)",
            "StartedAt": "-",
            "FinishedAt": "-",
        },
    }

    if args.output_path:
        output_path = Path(args.output_path)
        if not output_path.is_absolute():
            output_path = PROJECT_ROOT / output_path
        output_path.parent.mkdir(parents=True, exist_ok=True)
        report_path = output_path
    else:
        run_directory.mkdir(parents=True, exist_ok=True)
        report_path = run_directory / "odbc_operational_validation_report.md"

    failure_detected = False
    run_directory.mkdir(parents=True, exist_ok=True)
    health_snapshot_template_path = run_directory / "health_snapshot_template.json"

    try:
        Console.step("Health snapshot template")
        template_exit = run_streaming(
            [
                "dart",
                "run",
                "tool/odbc/export_odbc_health_snapshot_template.dart",
                "--output",
                str(health_snapshot_template_path),
            ]
        )
        if template_exit != 0:
            Console.warn("Health snapshot template generation failed.")
        else:
            update_context_from_health_snapshot_template(context, health_snapshot_template_path)
            Console.pass_("Health snapshot template generated.")

        def run_odbc_runtime() -> int:
            return run_streaming(
                [
                    "flutter",
                    "test",
                    "test/tool/odbc_fast_runtime_check_test.dart",
                ],
                log_path=run_directory / steps["OdbcRuntime"]["Log"],
            )

        succeeded, started, finished = invoke_step(
            "ODBC runtime",
            run_odbc_runtime,
            log_path=run_directory / steps["OdbcRuntime"]["Log"],
        )
        steps["OdbcRuntime"]["Status"] = "passed" if succeeded else "failed"
        steps["OdbcRuntime"]["StartedAt"] = started
        steps["OdbcRuntime"]["FinishedAt"] = finished
        if not succeeded:
            failure_detected = True
            raise RuntimeError("ODBC runtime failed.")

        if not args.skip_preflight:
            def run_preflight() -> int:
                return run_streaming(
                    ["dart", "run", "tool/e2e/check_e2e_env.dart"],
                    log_path=run_directory / steps["Preflight"]["Log"],
                )

            succeeded, started, finished = invoke_step(
                "Preflight",
                run_preflight,
                log_path=run_directory / steps["Preflight"]["Log"],
            )
            steps["Preflight"]["Status"] = "passed" if succeeded else "failed"
            steps["Preflight"]["StartedAt"] = started
            steps["Preflight"]["FinishedAt"] = finished
            if not succeeded:
                failure_detected = True
                raise RuntimeError("Preflight failed.")

        if args.run_smoke:
            def run_smoke() -> int:
                return run_streaming(
                    ["flutter", "test", "test/integration/odbc_queued_gateway_smoke_live_e2e_test.dart"],
                    log_path=run_directory / steps["Smoke"]["Log"],
                )

            succeeded, started, finished = invoke_step(
                "Smoke",
                run_smoke,
                log_path=run_directory / steps["Smoke"]["Log"],
            )
            steps["Smoke"]["Status"] = "passed" if succeeded else "failed"
            steps["Smoke"]["StartedAt"] = started
            steps["Smoke"]["FinishedAt"] = finished
            if not succeeded:
                failure_detected = True
                raise RuntimeError("Smoke failed.")

        if args.run_burst:
            os.environ["RUN_ODBC_BURST_TESTS"] = "true"
            os.environ["ODBC_BURST_HEALTH_SNAPSHOT_DIR"] = str(run_directory)
            context["RunOdbcBurstTests"] = "true"

            def run_burst() -> int:
                return run_streaming(
                    ["flutter", "test", "test/integration/sql_queue_burst_test.dart"],
                    log_path=run_directory / steps["Burst"]["Log"],
                )

            succeeded, started, finished = invoke_step(
                "Burst",
                run_burst,
                log_path=run_directory / steps["Burst"]["Log"],
            )
            steps["Burst"]["Status"] = "passed" if succeeded else "failed"
            steps["Burst"]["StartedAt"] = started
            steps["Burst"]["FinishedAt"] = finished
            if not succeeded:
                failure_detected = True
                raise RuntimeError("Burst failed.")

        if args.run_benchmark:
            def run_benchmark() -> int:
                return run_streaming(
                    [sys.executable, str(TOOL_DIR / "benchmarks" / "odbc_async_benchmark.py")],
                    log_path=run_directory / steps["Benchmark"]["Log"],
                )

            succeeded, started, finished = invoke_step(
                "Benchmark",
                run_benchmark,
                log_path=run_directory / steps["Benchmark"]["Log"],
            )
            steps["Benchmark"]["Status"] = "passed" if succeeded else "failed"
            steps["Benchmark"]["StartedAt"] = started
            steps["Benchmark"]["FinishedAt"] = finished
            if not succeeded:
                failure_detected = True
                raise RuntimeError("Benchmark failed.")

        if args.run_streaming_benchmark:
            def run_streaming_benchmark() -> int:
                return run_streaming(
                    [sys.executable, str(TOOL_DIR / "benchmarks" / "odbc_streaming_benchmark.py")],
                    log_path=run_directory / steps["StreamingBenchmark"]["Log"],
                )

            succeeded, started, finished = invoke_step(
                "Streaming benchmark",
                run_streaming_benchmark,
                log_path=run_directory / steps["StreamingBenchmark"]["Log"],
            )
            steps["StreamingBenchmark"]["Status"] = "passed" if succeeded else "failed"
            steps["StreamingBenchmark"]["StartedAt"] = started
            steps["StreamingBenchmark"]["FinishedAt"] = finished
            if not succeeded:
                failure_detected = True
                raise RuntimeError("Streaming benchmark failed.")

        if args.run_driver_matrix_benchmark:
            def run_driver_matrix() -> int:
                return run_streaming(
                    [
                        sys.executable,
                        str(TOOL_DIR / "benchmarks" / "odbc_driver_matrix_benchmark.py"),
                        "--output-directory",
                        str(run_directory),
                    ],
                    log_path=run_directory / steps["DriverMatrixBenchmark"]["Log"],
                )

            succeeded, started, finished = invoke_step(
                "Driver matrix benchmark",
                run_driver_matrix,
                log_path=run_directory / steps["DriverMatrixBenchmark"]["Log"],
            )
            steps["DriverMatrixBenchmark"]["Status"] = "passed" if succeeded else "failed"
            steps["DriverMatrixBenchmark"]["StartedAt"] = started
            steps["DriverMatrixBenchmark"]["FinishedAt"] = finished
            if not succeeded:
                failure_detected = True
                raise RuntimeError("Driver matrix benchmark failed.")
    except RuntimeError:
        pass
    finally:
        report_path.write_text(build_validation_report(context, steps), encoding="utf-8")
        print()
        Console._emit(Console.GRAY, f"Validation worksheet: {report_path}")
        Console._emit(Console.GRAY, f"Run artifacts directory: {run_directory}")
        Console._emit(
            Console.GRAY,
            "Burst health snapshots are written automatically when --run-burst or --all is used.",
        )

    return 1 if failure_detected else 0


if __name__ == "__main__":
    raise SystemExit(main())
