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
import subprocess
import sys
from pathlib import Path

_TOOL_DIR = Path(__file__).resolve().parent
if str(_TOOL_DIR) not in sys.path:
    sys.path.insert(0, str(_TOOL_DIR))

from py.script_utils import Console, PROJECT_ROOT, run_streaming

BUILD_SCRIPT = PROJECT_ROOT / "tool" / "build_elevated_runner.py"
BUILD_EXE = PROJECT_ROOT / "build" / "elevated_runner" / "plug_agente_elevated_runner.exe"
RELEASE_EXE = (
    PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Release" / "plug_agente_elevated_runner.exe"
)
TASK_NAME = r"PlugAgente\ElevatedActionRunner"

UNIT_TEST_PATHS = [
    "test/infrastructure/actions/elevated_action_runner_installer_test.dart",
    "test/application/actions/elevated_agent_action_execution_service_test.dart",
    "test/infrastructure/actions/elevated_action_request_protector_test.dart",
    "test/presentation/widgets/agent_actions/agent_action_confirmations_test.dart",
    "test/presentation/widgets/agent_actions/agent_action_risk_labels_test.dart",
]

MANUAL_STEPS = """  1. flutter run -d windows (or use installed build).
  2. Enable feature flag: Elevated agent actions.
  3. Actions page -> Prepare elevated runner (accept UAC for scheduled task).
  4. Create/edit action -> enable elevated (confirm dialog) -> Test -> Run.
  5. Verify execution succeeds; check diagnostics (no degraded elevated state).
  6. Optional: cancel/kill while running; retry after helper stop.

  Bridge dirs under app data: agent_actions/elevated/{requests,status,cancel,materialized}
  Ready marker: agent_actions/elevated/elevated_runner.ready

  See docs/testing/e2e_setup.md (Elevated action runner section).
"""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Pre-flight checks for Windows elevated action runner homologation.",
    )
    parser.add_argument("--build", action="store_true", help="Build helper before checks")
    parser.add_argument("--run-unit-tests", action="store_true", help="Run elevated-related unit tests")
    args = parser.parse_args()

    failed = False

    Console.step("Platform")
    if os.name != "nt":
        Console.fail("Elevated runner homologation requires Windows.")
        return 1
    Console.pass_("Windows detected.")

    Console.step("Helper executable")
    if args.build or not BUILD_EXE.is_file():
        if not BUILD_SCRIPT.is_file():
            Console.fail(f"Missing build script: {BUILD_SCRIPT}")
            return 1
        print(f"  Building via {BUILD_SCRIPT} ...")
        build_result = subprocess.run([sys.executable, str(BUILD_SCRIPT)], check=False)
        if build_result.returncode != 0:
            Console.fail("build_elevated_runner.py failed.")
            return build_result.returncode

    if BUILD_EXE.is_file():
        Console.pass_(f"Build output: {BUILD_EXE}")
    else:
        Console.fail(f"Helper not found at {BUILD_EXE} (run with --build).")
        failed = True

    if RELEASE_EXE.is_file():
        Console.pass_(f"Bundled next to app runner: {RELEASE_EXE}")
    else:
        Console.warn(
            f"Release bundle missing: {RELEASE_EXE} (run flutter build windows or copy helper manually)."
        )

    env_exe = os.environ.get("ELEVATED_ACTION_RUNNER_EXE")
    if env_exe:
        if Path(env_exe).is_file():
            Console.pass_(f"ELEVATED_ACTION_RUNNER_EXE exists: {env_exe}")
        else:
            Console.fail(f"ELEVATED_ACTION_RUNNER_EXE points to missing file: {env_exe}")
            failed = True
    else:
        Console.warn("ELEVATED_ACTION_RUNNER_EXE not set (resolver uses sibling of plug_agente.exe).")

    Console.step("Scheduled task (optional until UI Prepare)")
    task_result = subprocess.run(
        ["schtasks.exe", "/Query", "/TN", TASK_NAME, "/FO", "LIST"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        check=False,
    )
    if task_result.returncode == 0:
        Console.pass_(f"Scheduled task registered: {TASK_NAME}")
    else:
        Console.warn("Scheduled task not found yet. Use Actions page -> Prepare elevated runner.")

    if args.run_unit_tests:
        Console.step("Unit tests (no UAC)")
        test_exit = run_streaming(["flutter", "test", *UNIT_TEST_PATHS])
        if test_exit != 0:
            Console.fail("Elevated-related unit tests failed.")
            failed = True
        else:
            Console.pass_("Elevated-related unit tests passed.")
    else:
        Console.warn("Skipped unit tests. Re-run with --run-unit-tests for automated gate.")

    Console.step("Manual homologation (UI + UAC)")
    print(MANUAL_STEPS)

    if failed:
        print()
        Console.fail("Pre-flight checks failed. Fix issues above before field homologation.")
        return 1

    print()
    Console.pass_("Pre-flight checks complete. Continue with manual steps above.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
