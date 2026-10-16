"""Coordinated persona-v2 cutover gate. A partial implementation must not ship."""
import json
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

if __name__ == "__main__":
    manifest = json.loads((Path(__file__).resolve().parents[2] / "contracts/persona-v2-release.json").read_text(encoding="utf-8"))
    if not ready(manifest):
        raise SystemExit("Publication blocked: persona-v2 coordinated acceptance is incomplete.")
