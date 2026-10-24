"""Reverify the inputs and outputs of an isolated bootstrap application build."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

from tool.updater.application_source import ENTRYPOINT, SAFE_ENV, blob_hash, derived_bytes, git_files, git_output, relative_name, requires_native_derivation, source_bytes, source_root
from tool.updater.isolated_windows_fixture import require_fixture_root, require_fixture_artifact, require_identity
from tool.updater.lifecycle_payload import capture_payload, payload_tree_hash

MAX_PROOF_BYTES = 2 * 1024 * 1024


def canonical_hash(files: dict[str, str]) -> str:
    return hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode()).hexdigest()


def verify_sources(root: Path, revision: str, identity: str, expected: dict[str, str]) -> None:
    originals = git_files(revision)
    if not isinstance(expected, dict) or set(expected) != set(originals) | {".env"}:
        raise RuntimeError("Application source inventory does not match the selected commit")
    for name, digest in expected.items():
        relative_name(name)
        if not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise RuntimeError("Invalid application source digest")
        content = source_bytes(root, name)
        if hashlib.sha256(content).hexdigest() != digest:
            raise RuntimeError("Application source changed after capture")
        if name == ".env":
            if content != SAFE_ENV:
                raise RuntimeError("Unexpected application environment input")
        elif requires_native_derivation(name) or blob_hash(content) != originals[name]:
            original = git_output("show", f"{revision}:{name}")
            if derived_bytes(name, original, identity) != content:
                raise RuntimeError("Application derivation does not match the selected commit")


def load_application_build(path: Path) -> dict:
    if path.name != "application-build.json":
        raise RuntimeError("The owned application-build.json is required")
    root = require_fixture_root(path.parent)
    path = require_fixture_artifact(root, path)
    if path.stat().st_size > MAX_PROOF_BYTES:
        raise RuntimeError("Application proof exceeds its size limit")
    state = json.loads(path.read_text(encoding="utf-8"))
    if (type(state.get("format")) is not int or state["format"] != 1
            or state.get("scope") != "source-qualified-isolated-bootstrap"
            or state.get("productionActivationGate") is not False
            or state.get("entrypoint") != ENTRYPOINT or Path(state["root"]) != root):
        raise RuntimeError("Unsupported application-build proof")
    identity = require_identity(state["identity"])
    source = source_root(identity)
    if Path(state["sourceRoot"]) != source:
        raise RuntimeError("Application source root does not match its identity")
    files = state.get("sourceFiles")
    verify_sources(source, state["revision"], identity, files)
    if state.get("sourceTreeSha256") != canonical_hash(files):
        raise RuntimeError("Application source-tree binding mismatch")
    if "runtimeInput" in state:
        from tool.updater.isolated_runtime import verify_runtime_reference, load_runtime
        verify_runtime_reference(state["runtimeInput"], root)
        runtime = load_runtime(Path(state["runtimeInput"]["path"]))
        if any(state.get("payloadFiles", {}).get(name) != metadata["sha256"] for name, metadata in runtime["files"].items()):
            raise RuntimeError("Application payload does not contain the verified private runtime")
    actual = capture_payload(root)
    if actual != state.get("payloadFiles") or payload_tree_hash(actual) != state.get("payloadTreeSha256"):
        raise RuntimeError("Application build payload changed")
    return state
