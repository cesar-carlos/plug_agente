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
import subprocess
import sys

from py.script_utils import Console, PROJECT_ROOT, read_manifest_test_paths, run, run_streaming


MANUAL_CHECKLIST = """  1. Hub must advertise extensions.agentActions in agent:capabilities (set E2E_HUB_EXPECT_AGENT_ACTIONS_CAPABILITY=true to assert).
  2. For inbound RPC smoke, hub must emit agent.action.* after agent:ready (E2E_HUB_EXPECT_AGENT_ACTION_RPC=true).
  3. Production: enforce allowlist/rate limit on Hub; agent already routes agent.action.run/validateRun/cancel/getExecution.
  4. Register COM handlers in com_object_production_registrations.dart (or AGENT_ACTION_COM_STUB_* for homologation).
  5. Homologation COM stub: AGENT_ACTION_COM_STUB_ENABLED=true plus PROG_ID/MEMBER_NAME in .env (see docs/testing/e2e_setup.md).
  6. Security gate per type: dart run tool/agent_actions/agent_action_security_gate_checklist.dart [type]
"""

HUB_SOCKET_CONNECT_FAIL = """Hub Socket connect smoke failed (check E2E_HUB_URL and E2E_HUB_TOKEN).
If the error mentions jwt expired, refresh the token:
  dart run tool/e2e/fetch_e2e_hub_token_from_local_config.dart --apply-token --force
(sign in via Config, E2E_HUB_USERNAME/PASSWORD in .env, or set E2E_HUB_TOKEN from Hub admin).
"""

SIGNED_CAPABILITIES_FAIL = """Signed capabilities smoke failed. Socket connect succeeded but agent:capabilities did not arrive.
- Use the same PAYLOAD_SIGNING_KEY_ID and PAYLOAD_SIGNING_KEY as the deployed Hub (not e2e-dev on production).
- dart run tool/e2e/export_e2e_secrets_from_local.dart
- dart run tool/e2e/promote_e2e_signing_from_monorepo_env.dart
- dart run tool/e2e/validate_live_hub_agent_actions_env.dart
"""


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Pre-flight checks for Hub agent.action.* homologation.",
    )
    parser.add_argument("--run-contract-tests", action="store_true")
    parser.add_argument("--run-live-tests", action="store_true")
    parser.add_argument("--validate-live-env", action="store_true")
    parser.add_argument("--prepare-live-env", action="store_true")
    args = parser.parse_args()

    Console.step("E2E environment")
    result = run(["dart", "run", "tool/e2e/check_e2e_env.dart"], check=False)
    if result.returncode != 0:
        Console.fail("check_e2e_env.dart failed.")
        return result.returncode
    Console.pass_("check_e2e_env.dart completed.")

    if args.prepare_live_env:
        Console.step("Prepare live Hub .env from local app storage")
        sync_result = run(
            ["dart", "run", "tool/e2e/sync_e2e_hub_env_from_local.dart", "--export-secure"],
            check=False,
        )
        if sync_result.returncode != 0:
            Console.warn("sync_e2e_hub_env_from_local.dart finished with missing variables (see hints above).")
        else:
            Console.pass_("sync_e2e_hub_env_from_local.dart completed.")

        Console.step("Promote signing from plug_server/.env (monorepo)")
        promote_result = run(
            ["dart", "run", "tool/e2e/promote_e2e_signing_from_monorepo_env.dart", "--force"],
            check=False,
        )
        if promote_result.returncode != 0:
            Console.step("Generate dev signing pair (agent + sibling plug_server/.env)")
            generate_result = run(
                ["dart", "run", "tool/e2e/generate_dev_e2e_signing.dart", "--write"],
                check=False,
            )
            if generate_result.returncode != 0:
                Console.warn("generate_dev_e2e_signing.dart failed.")
        else:
            Console.pass_("Signing keys promoted from monorepo.")

        Console.step("Refresh E2E_HUB_TOKEN (local DB, saved credentials, or E2E_HUB_USERNAME/PASSWORD)")
        token_result = run(
            [
                "dart",
                "run",
                "tool/e2e/fetch_e2e_hub_token_from_local_config.dart",
                "--apply-token",
                "--force",
            ],
            check=False,
        )
        if token_result.returncode != 0:
            Console.warn(
                "Token refresh skipped - sign in via Config or set E2E_HUB_TOKEN / E2E_HUB_USERNAME in .env."
            )
        else:
            Console.pass_("E2E_HUB_TOKEN refresh attempted.")

    if args.validate_live_env:
        Console.step("Live Hub agent.action preflight")
        validate_result = run(
            ["dart", "run", "tool/e2e/validate_live_hub_agent_actions_env.dart"],
            check=False,
        )
        if validate_result.returncode != 0:
            Console.fail("validate_live_hub_agent_actions_env.dart failed.")
            return validate_result.returncode
        Console.pass_(
            "Live Hub variables present (run --run-live-tests to execute hub_agent_action_rpc_live_e2e_test.dart)."
        )

    if args.run_contract_tests:
        Console.step("Agent actions production preflight (static)")
        preflight_result = run(
            ["dart", "run", "tool/agent_actions/preflight_agent_actions_production.dart"],
            check=False,
        )
        if preflight_result.returncode != 0:
            Console.fail("Production preflight failed.")
            return preflight_result.returncode
        Console.pass_("Production preflight passed.")

        Console.step("Agent action contract tests (local)")
        contract_paths = read_manifest_test_paths("agent_actions_contract_test_paths.txt")
        contract_exit = run_streaming(["flutter", "test", *contract_paths])
        if contract_exit != 0:
            Console.fail("Contract tests failed.")
            return contract_exit
        Console.pass_("Contract tests passed.")

        Console.step("Agent actions UI regression (local)")
        ui_paths = read_manifest_test_paths("agent_actions_ui_test_paths.txt")
        ui_exit = run_streaming(["flutter", "test", *ui_paths])
        if ui_exit != 0:
            Console.fail("UI regression tests failed.")
            return ui_exit
        Console.pass_("UI regression tests passed.")
    else:
        Console.warn("Skipped contract tests (use --run-contract-tests).")

    if args.run_live_tests:
        Console.step("Hub Socket smoke (connect)")
        connect_exit = run_streaming(
            [
                "flutter",
                "test",
                "test/integration/hub_socket_live_e2e_test.dart",
                "--name",
                "should connect",
            ]
        )
        if connect_exit != 0:
            Console.fail(HUB_SOCKET_CONNECT_FAIL)
            return connect_exit
        Console.pass_("Hub Socket connect smoke passed.")

        Console.step("Hub signed capabilities smoke (PAYLOAD_SIGNING_* must match Hub)")
        signed_exit = run_streaming(
            [
                "flutter",
                "test",
                "test/integration/hub_socket_live_e2e_test.dart",
                "--name",
                "signed PayloadFrame",
            ]
        )
        if signed_exit != 0:
            Console.fail(SIGNED_CAPABILITIES_FAIL)
            return signed_exit
        Console.pass_("Hub signed capabilities smoke passed.")

        Console.step("Hub agent.action live tests (opt-in)")
        live_exit = run_streaming(
            [
                "flutter",
                "test",
                "test/integration/hub_agent_action_rpc_live_e2e_test.dart",
                "--tags",
                "live",
            ]
        )
        if live_exit != 0:
            Console.fail("Live hub agent.action tests failed.")
            return live_exit
        Console.pass_("Live hub agent.action tests passed.")
    else:
        Console.warn("Skipped live tests (use --run-live-tests after configuring .env).")

    Console.step("Manual checklist")
    Console._emit(Console.GRAY, MANUAL_CHECKLIST)
    if args.run_contract_tests:
        subprocess.run(
            ["dart", "run", "tool/agent_actions/agent_action_security_gate_checklist.dart"],
            cwd=PROJECT_ROOT,
            check=False,
        )
    Console.pass_("Homologation script finished.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
