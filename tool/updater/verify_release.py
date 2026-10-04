"""Verify a signed manifest against the actual release asset, before feed publication."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path

from tool.updater.manifest import verify


def verify_release(manifest: Path, installer: Path, keys: str, version: str, channel: str, source_commit: str | None = None) -> dict:
    if manifest.stat().st_size > 131072:
        raise ValueError("Manifest exceeds size limit")
    envelope = json.loads(manifest.read_text(encoding="utf-8"))
    payload = verify(envelope, [key.strip() for key in keys.split(",") if key.strip()])
    with installer.open("rb") as source:
        digest = hashlib.file_digest(source, "sha256").hexdigest()
    if payload["version"] != version or payload["channel"] != channel:
        raise ValueError("Release manifest identity mismatch")
    if source_commit is not None and payload["release"]["commit"] != source_commit:
        raise ValueError("Release source commit does not match signed manifest")
    if payload["installer"]["size"] != installer.stat().st_size or payload["installer"]["sha256"] != digest:
        raise ValueError("Release asset does not match signed manifest")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--installer", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--channel", required=True)
    parser.add_argument("--source-commit", required=True)
    args = parser.parse_args()
    keys = os.environ.get("AUTO_UPDATE_FEED_PUBLIC_KEY", "")
    if not keys:
        raise SystemExit("Trusted manifest public keys are required")
    verify_release(args.manifest, args.installer, keys, args.version, args.channel, args.source_commit)
    print("Signed manifest and release asset verified")


if __name__ == "__main__":
    main()
