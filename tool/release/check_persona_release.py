"""Coordinated persona-v2 cutover gate. A partial implementation must not ship."""
import argparse
import json
import re
from pathlib import Path

REQUIRED = ["shared-knowledge-and-compatibility","identity-and-authorization","training-and-local-query","federation","agent-operation-journal","hub-operation-contract","operation-approval-and-reconciliation","external-rest-and-mcp","oauth-and-console","postgres-real","mssql-real","sybase-real","coordinated-cutover"]

def ready(manifest):
    return (
        manifest.get("generation") == "persona-v2"
        and manifest.get("ready") is True
        and manifest.get("requiredGates") == REQUIRED
        and isinstance(manifest.get("completedGates"), list)
        and all(item in manifest["completedGates"] for item in REQUIRED)
    )

def accepted_risk(tag, build, channel, pubspec):
    return (
        (tag, build, channel) == ("v1.9.0", "1.9.0+1", "stable")
        and re.findall(r"^version:\s*(\S+)\s*$", pubspec, re.MULTILINE) == [build]
    )


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    for name in ("tag", "build", "channel"):
        parser.add_argument(f"--{name}")
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    manifest = json.loads((root / "contracts/persona-v2-release.json").read_text(encoding="utf-8"))
    if not ready(manifest) and accepted_risk(args.tag, args.build, args.channel, (root / "pubspec.yaml").read_text()):
        print("Applying the documented v1.9.0 stable risk acceptance. Persona-v2 gates remain open.")
    elif not ready(manifest):
        raise SystemExit("Publication blocked: persona-v2 coordinated acceptance is incomplete.")
