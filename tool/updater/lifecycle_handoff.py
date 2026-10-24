"""One-attempt coordination evidence for isolated Windows lifecycle phases."""
import hashlib
import json
import os
from pathlib import Path
import re
import secrets

from tool.updater.isolated_windows_fixture import require_fixture_root, require_fixture_artifact

READY = "standard-phase-ready"
CLAIM = "standard-phase-claim.json"
RESULT = "standard-result.json"
CHECKS = frozenset({
    "real_scm_pipe_identity_and_activation_gate", "control_directory_write_denied",
    "protected_policy_read_denied", "unregistered_client_image_refused",
    "administrative_transitions_denied", "real_user_dpapi_roundtrip",
    "replay_channel_capability_and_signature_refused",
    "real_signed_staging_idempotence_blocked_apply_and_cancel",
    "twenty_signed_prepare_cancel_cycles",
})


def has_entry(path: Path) -> bool:
    try:
        path.lstat()
    except FileNotFoundError:
        return False
    return True


def assert_fresh(state: dict) -> None:
    root = Path(state["root"])
    if any(has_entry(root / name) for name in (READY, CLAIM, RESULT, RESULT + ".tmp")):
        raise RuntimeError("Refusing previous standard-user phase evidence; provision a new fixture")


def read_owned(root: Path, name: str) -> dict:
    path = require_fixture_artifact(root, root / name)
    if path.stat().st_nlink != 1 or path.stat().st_size > 8192:
        raise RuntimeError("Invalid lifecycle phase evidence file")
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise RuntimeError("Invalid lifecycle phase evidence object")
    return value


def fixture_binding(state: dict) -> str:
    root = require_fixture_root(Path(state["root"]))
    manifest = require_fixture_artifact(root, root / "fixture.json")
    if manifest.stat().st_nlink != 1 or manifest.stat().st_size > 256 * 1024:
        raise RuntimeError("Invalid lifecycle manifest for phase binding")
    value = {"root": str(root), "manifest": hashlib.sha256(manifest.read_bytes()).hexdigest(),
             "identity": state["identity"], "installer": state["installerSha256"],
             "payload": state["payloadTreeSha256"]}
    return hashlib.sha256(json.dumps(value, sort_keys=True, separators=(",", ":")).encode()).hexdigest()


def create_handoff(state: dict) -> dict:
    assert_fresh(state)
    root = require_fixture_root(Path(state["root"]))
    handoff = {"format": "isolated-lifecycle-handoff-v1", "phaseId": secrets.token_hex(32),
               "fixtureBinding": fixture_binding(state)}
    with (root / READY).open("x", encoding="utf-8") as output:
        json.dump(handoff, output)
    return handoff


def claim_handoff(state: dict) -> dict:
    root = require_fixture_root(Path(state["root"]))
    if has_entry(root / "lifecycle-result.json"):
        raise RuntimeError("Administrator phase already ended; never resume the standard-user phase")
    if has_entry(root / RESULT):
        raise RuntimeError("Standard-user result already exists; never repeat the phase")
    handoff = read_owned(root, READY)
    if (set(handoff) != {"format", "phaseId", "fixtureBinding"}
            or handoff.get("format") != "isolated-lifecycle-handoff-v1"
            or not isinstance(handoff.get("phaseId"), str)
            or not re.fullmatch(r"[a-f0-9]{64}", handoff["phaseId"])
            or handoff.get("fixtureBinding") != fixture_binding(state)):
        raise RuntimeError("Standard-user handoff does not match the current fixture")
    with (root / CLAIM).open("x", encoding="utf-8") as output:
        json.dump(handoff, output)
    return handoff


def result_binding(handoff: dict) -> dict:
    return {"format": "isolated-standard-result-v1", "phaseId": handoff["phaseId"],
            "fixtureBinding": handoff["fixtureBinding"]}


def verify_result(state: dict, handoff: dict) -> None:
    root = require_fixture_root(Path(state["root"]))
    if handoff["fixtureBinding"] != fixture_binding(state) or read_owned(root, CLAIM) != handoff:
        raise RuntimeError("Standard-user phase binding changed")
    result = read_owned(root, RESULT)
    checks = result.get("checks")
    if (any(result.get(key) != value for key, value in result_binding(handoff).items())
            or result.get("status") != "passed" or result.get("elevated") is not False
            or not isinstance(checks, list) or not all(isinstance(check, str) for check in checks)
            or len(checks) != len(CHECKS) or set(checks) != CHECKS):
        raise RuntimeError("Standard-user phase evidence is incomplete or belongs to another attempt")


def write_result(state: dict, result: dict) -> None:
    if os.name != "nt":
        raise RuntimeError("Atomic lifecycle result publication requires Windows")
    root = require_fixture_root(Path(state["root"]))
    target = root / RESULT
    if has_entry(target):
        raise RuntimeError("Standard-user result already exists; never overwrite evidence")
    pending = root / (RESULT + ".tmp")
    with pending.open("x", encoding="utf-8") as output:
        json.dump(result, output, indent=2)
        output.flush()
        os.fsync(output.fileno())
    # Windows rename refuses an existing target; no replace/overwrite flag.
    pending.rename(target)
