#!/usr/bin/env python3
"""Unified ODBC pre-release gate for plug_agente.

Native block-fetch batch size is tuned via process env `ODBC_FAST_BLOCK_FETCH_BATCH`
(read by odbc_fast at runtime; no plug_agente code hook required).
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
import os
import subprocess
import sys
from pathlib import Path

os.environ.setdefault("PYTHONIOENCODING", "utf-8")

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.py.script_utils import PROJECT_ROOT, ensure_utf8_stdio, import_dotenv_if_present, resolve_env_path, run_streaming

ensure_utf8_stdio()


def _run(command: list[str], *, log_path: Path | None = None) -> int:
    env = os.environ.copy()
    env.setdefault("PYTHONIOENCODING", "utf-8")
    if log_path is not None:
        return run_streaming(command, cwd=PROJECT_ROOT, log_path=log_path, env=env)
    result = subprocess.run(command, cwd=PROJECT_ROOT, check=False, env=env)
    return int(result.returncode)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Run plug_agente ODBC release gate.")
    parser.add_argument("--env-path", default=".env", help="Path to .env (default: .env)")
    parser.add_argument("--skip-analyze", action="store_true", help="Skip dart analyze.")
    parser.add_argument("--skip-unit-tests", action="store_true", help="Skip flutter test odbc_* suites.")
    parser.add_argument(
        "--require-columnar-compressed",
        action="store_true",
        help="Pass --require-columnar-compressed to check_odbc_fast_runtime.",
    )
    parser.add_argument(
        "--run-benchmark-gate",
        action="store_true",
        help="Run benchmark suite with BENCHMARK_ENFORCE_ODBC_GATES=1 when ODBC DSN is configured.",
    )
    parser.add_argument(
        "--run-operational-validation",
        action="store_true",
        help="Run tool/odbc/run_odbc_operational_validation.py (runtime + preflight).",
    )
    parser.add_argument("--output-dir", default="", help="Output directory for operational validation.")
    args = parser.parse_args(argv)

    import_dotenv_if_present(resolve_env_path(args.env_path))
    output_dir = Path(args.output_dir) if args.output_dir else PROJECT_ROOT / "artifacts" / "odbc_release_gate"
    output_dir.mkdir(parents=True, exist_ok=True)

    steps: list[tuple[str, int]] = []

    if not args.skip_analyze:
        steps.append(
            (
                "dart_analyze",
                _run(["dart", "analyze"], log_path=output_dir / "dart_analyze.log"),
            )
        )

    if not args.skip_unit_tests:
        steps.append(
            (
                "odbc_unit_tests",
                _run(
                    [
                        "flutter",
                        "test",
                        "--reporter",
                        "expanded",
                        "test/infrastructure/external_services/odbc_columnar_stream_chunk_mapper_test.dart",
                        "test/infrastructure/external_services/odbc_streaming_named_parameter_preparer_test.dart",
                        "test/infrastructure/external_services/native_compatible_acquire_policy_test.dart",
                        "test/infrastructure/external_services/odbc_streaming_gateway_test.dart",
                        "test/infrastructure/config/odbc_stream_wire_config_test.dart",
                        "test/infrastructure/config/odbc_usage_profile_config_test.dart",
                        "test/infrastructure/config/odbc_performance_preset_config_test.dart",
                    ],
                    log_path=output_dir / "odbc_unit_tests.log",
                ),
            )
        )

    runtime_cmd = ["dart", "run", "tool/odbc/check_odbc_fast_runtime.dart"]
    if args.require_columnar_compressed:
        runtime_cmd.append("--require-columnar-compressed")
    steps.append(
        (
            "odbc_fast_runtime",
            _run(runtime_cmd, log_path=output_dir / "odbc_fast_runtime.log"),
        )
    )

    steps.append(
        (
            "odbc_pool_modes_launcher",
            _run(["dart", "run", "tool/benchmarks/benchmark_odbc_pool_modes.dart"], log_path=output_dir / "odbc_pool_modes.log"),
        )
    )

    if args.run_operational_validation:
        validation_cmd = [
            sys.executable,
            "tool/odbc/run_odbc_operational_validation.py",
            "--output-directory",
            str(output_dir / "operational_validation"),
        ]
        steps.append(
            (
                "operational_validation",
                _run(validation_cmd, log_path=output_dir / "operational_validation.log"),
            )
        )

    if args.run_benchmark_gate:
        benchmark_cmd = [
            sys.executable,
            "tool/benchmarks/run_benchmark_suite.py",
            "--skip-dart-tool",
            "--only",
            "odbc_async,odbc_streaming",
            "--output-dir",
            str(output_dir / "benchmark"),
        ]
        import os

        os.environ["BENCHMARK_ENFORCE_ODBC_GATES"] = "1"
        os.environ.setdefault("PYTHONIOENCODING", "utf-8")
        benchmark_log = output_dir / "benchmark_gate.log"
        if benchmark_log.is_file():
            benchmark_log.unlink()
        steps.append(
            (
                "benchmark_gate",
                _run(benchmark_cmd, log_path=output_dir / "benchmark_gate.log"),
            )
        )

    failed = [name for name, code in steps if code != 0]
    print()
    print("ODBC release gate summary")
    for name, code in steps:
        print(f"- {name}: {'pass' if code == 0 else f'fail ({code})'}")
    print(f"Artifacts: {output_dir}")

    return 1 if failed else 0


if __name__ == "__main__":
    raise SystemExit(main())
