"""Explicit application-build binding for private lifecycle packages."""
from pathlib import Path

from tool.updater.application_build_proof import load_application_build
from tool.updater.validate_windows_installation import sha256

# These tools are rebuilt with the lifecycle fixture public key.
REBUILT_TOOLS = frozenset(f"updater/plug_update_{name}.exe" for name in ("service", "client", "worker"))


def application_input(path: Path) -> tuple[dict, dict]:
    state = load_application_build(path)
    reference = {"path": str(path.absolute()), "sha256": sha256(path),
                 "revision": state["revision"], "sourceTreeSha256": state["sourceTreeSha256"],
                 "payloadTreeSha256": state["payloadTreeSha256"]}
    # Detect replacement during proof verification without trusting either read.
    if load_application_build(path) != state or sha256(path) != reference["sha256"]:
        raise RuntimeError("Application build changed during package binding")
    return state, reference


def verify_application_package(reference: dict, identity: str, payload_files: dict) -> None:
    if not isinstance(reference, dict) or not isinstance(reference.get("path"), str):
        raise RuntimeError("An explicit application-build reference is required")
    state, current = application_input(Path(reference["path"]))
    if current != reference or state["identity"] != identity:
        raise RuntimeError("Application build reference or package identity changed")
    expected = {name: digest for name, digest in state["payloadFiles"].items() if name not in REBUILT_TOOLS}
    actual = {name: digest for name, digest in payload_files.items() if name not in REBUILT_TOOLS}
    if actual != expected:
        raise RuntimeError("Packaged application differs from its verified build")
