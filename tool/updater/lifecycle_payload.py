"""Byte-level payload binding for private installer lifecycle fixtures."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path, PurePosixPath
import re

from installer.build_installer import PROJECT_EXECUTABLES
from tool.updater.isolated_windows_fixture import require_fixture_root, require_fixture_artifact, reject_reparse
from tool.updater.validate_windows_installation import sha256

REQUIRED_PAYLOAD_FILES = frozenset((*PROJECT_EXECUTABLES, "data/app.so"))
MAX_PAYLOAD_FILES = 4096


def validate_payload_files(value: object) -> dict[str, str]:
    if not isinstance(value, dict) or not value or len(value) > MAX_PAYLOAD_FILES:
        raise RuntimeError("Invalid fixture payload inventory")
    for name, digest in value.items():
        if (not isinstance(name, str) or not re.fullmatch(r"[^\\:\x00-\x1f]+", name)
                or PurePosixPath(name).is_absolute() or PurePosixPath(name).as_posix() != name
                or any(part in {".", ".."} for part in PurePosixPath(name).parts)
                or not isinstance(digest, str) or not re.fullmatch(r"[a-f0-9]{64}", digest)):
            raise RuntimeError("Invalid fixture payload inventory entry")
    if not REQUIRED_PAYLOAD_FILES.issubset(value):
        raise RuntimeError("Required fixture payload files are missing")
    return value


def payload_tree_hash(files: dict[str, str]) -> str:
    validate_payload_files(files)
    return hashlib.sha256(json.dumps(files, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")).hexdigest()


def capture_payload(root: Path) -> dict[str, str]:
    root = require_fixture_root(root)
    payload = root / "payload"
    reject_reparse(payload)
    if not payload.is_dir():
        raise RuntimeError("Fixture payload directory is missing")
    pending = [payload]
    files = {}
    while pending:
        directory = pending.pop()
        for path in sorted(directory.iterdir()):
            # Check each entry before descending or opening any file.
            reject_reparse(path)
            if path.is_dir():
                pending.append(path)
            elif path.is_file():
                if path.stat().st_nlink != 1:
                    raise RuntimeError("Hard-linked or unproven fixture payload file is refused")
                if len(files) >= MAX_PAYLOAD_FILES:
                    raise RuntimeError("Fixture payload inventory exceeds its limit")
                artifact = require_fixture_artifact(root, path)
                files[artifact.relative_to(payload).as_posix()] = sha256(artifact)
            else:
                raise RuntimeError("Fixture payload contains a non-regular entry")
    return validate_payload_files(files)


def verify_payload(root: Path, expected: object, tree_hash: object) -> None:
    files = validate_payload_files(expected)
    if not isinstance(tree_hash, str) or tree_hash != payload_tree_hash(files):
        raise RuntimeError("Fixture payload inventory hash mismatch")
    if capture_payload(root) != files:
        raise RuntimeError("Fixture payload changed; reprovision before lifecycle execution")
