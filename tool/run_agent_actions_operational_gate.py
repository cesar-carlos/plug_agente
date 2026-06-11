#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

from py.script_utils import Console, TOOL_DIR


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Local/CI operational gate for agent actions.",
    )
    parser.add_argument(
        "--strict-com",
        action="store_true",
        help="Enable strict COM handler checks in production preflight",
    )
    args = parser.parse_args()

    preflight_script = TOOL_DIR / "preflight_agent_actions_production.py"
    preflight_args = [sys.executable, str(preflight_script), "--run-contract-tests"]
    if args.strict_com:
        preflight_args.append("--strict-com")

    result = subprocess.run(preflight_args, check=False)
    if result.returncode != 0:
        return result.returncode

    print()
    Console._emit(Console.GREEN, "Operational gate (local/CI) passed.")
    Console._emit(Console.CYAN, "Next steps (see plano - Roteiro operacional pos-MVP):")
    print("  3. dart run tool/agent_action_security_gate_checklist.dart [tipo]")
    print(
        "  4-6. python tool/homologate_hub_agent_actions.py "
        "--prepare-live-env --validate-live-env --run-live-tests"
    )
    print("  7. COM handlers in com_object_production_registrations.dart (or RA-01)")
    print("  8. Hub allowlist/rate limit (cross-repo, RA-02)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
