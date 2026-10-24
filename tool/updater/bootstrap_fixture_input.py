"""Verify a compiled bootstrap fixture and allocate its private runtime workspace."""
import argparse
import json
import os
from pathlib import Path
import tempfile

from tool.updater.application_package_binding import application_input
from tool.updater.validate_existing_windows_installation import protect_backup


def prepare(proof: Path) -> dict:
    if os.name != "nt":
        raise RuntimeError("Compiled bootstrap fixtures require Windows")
    state, reference = application_input(proof)
    root = Path(tempfile.mkdtemp(prefix="sql-operation-bootstrap-"))
    protect_backup(root)
    return {"format": "native-bootstrap-input-v1", "root": str(root.resolve()),
            "revision": state["revision"], "identity": state["identity"],
            "proofSha256": reference["sha256"],
            "executable": str(Path(state["root"]) / "payload/plug_agente.exe")}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--proof", type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.proof.absolute()), sort_keys=True))
