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
from pathlib import Path

from py.script_utils import Console, PROJECT_ROOT, TOOL_DIR, run


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Production-readiness preflight for agent actions (static + optional contract gate).",
    )
    parser.add_argument("--run-contract-tests", action="store_true")
    parser.add_argument("--validate-live-env", action="store_true")
    parser.add_argument("--prepare-live-env", action="store_true")
    parser.add_argument("--run-live-tests", action="store_true")
    parser.add_argument("--strict-com", action="store_true")
    args = parser.parse_args()

    Console.step("Agent actions production preflight (static)")
    dart_args = ["dart", "run", "tool/agent_actions/preflight_agent_actions_production.dart"]
    if args.strict_com:
        dart_args.append("--strict-com")
    result = run(dart_args, check=False)
    if result.returncode != 0:
        Console.fail("preflight_agent_actions_production.dart reported failures.")
        return result.returncode
    Console.pass_("Static production preflight passed.")

    homologate_flags = {
        "--run-contract-tests": args.run_contract_tests,
        "--validate-live-env": args.validate_live_env,
        "--prepare-live-env": args.prepare_live_env,
        "--run-live-tests": args.run_live_tests,
    }
    selected = [flag for flag, enabled in homologate_flags.items() if enabled]

    if selected:
        Console.step("Homologation gate")
        homologate_script = TOOL_DIR / "agent_actions" / "homologate_hub_agent_actions.py"
        homologate_args = [sys.executable, str(homologate_script), *selected]
        homologate_result = subprocess.run(homologate_args, cwd=PROJECT_ROOT, check=False)
        if homologate_result.returncode != 0:
            Console.fail("homologate_hub_agent_actions.py failed.")
            return homologate_result.returncode
        Console.pass_("Homologation gate passed.")
    else:
        Console.hint("Add --run-contract-tests and/or --validate-live-env for deeper checks.")

    Console.pass_("Production preflight finished.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
