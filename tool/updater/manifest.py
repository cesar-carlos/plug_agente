"""Signed updater contract. The signature covers the exact UTF-8 payload bytes."""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
from pathlib import Path

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey, Ed25519PublicKey

FORMAT_VERSION = 1
MAX_ENVELOPE_BYTES = 65536
DEFAULT_CAPABILITIES = ["app.files", "app.protocol", "autostart.user", "runtime.vc", "updater.worker"]


def canonical_payload(payload: dict) -> bytes:
    validate_payload(payload)
    return json.dumps(payload, ensure_ascii=False, sort_keys=True, separators=(",", ":"), allow_nan=False).encode("utf-8")


def validate_payload(payload: dict) -> None:
    required = {"formatVersion", "version", "channel", "installer", "requirements", "protocol", "data", "release"}
    if set(payload) != required or type(payload["formatVersion"]) is not int or payload["formatVersion"] != FORMAT_VERSION:
        raise ValueError("Unsupported manifest contract")
    if len(payload["version"]) > 128 or not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+", payload["version"]):
        raise ValueError("Invalid manifest version")
    if payload["channel"] not in {"stable", "beta", "internal"}:
        raise ValueError("Invalid channel")
    release = payload["release"]
    if set(release) != {"commit", "tag"} or not re.fullmatch(r"[a-f0-9]{40}", release["commit"]) or release["tag"] != "v" + payload["version"].split("+")[0]:
        raise ValueError("Invalid release source identity")
    installer = payload["installer"]
    if set(installer) != {"name", "size", "sha256"}:
        raise ValueError("Invalid installer metadata")
    expected_name = f"PlugAgente-Setup-{payload['version'].split('+')[0]}.exe"
    if installer["name"] != expected_name or type(installer["size"]) is not int or installer["size"] <= 0:
        raise ValueError("Invalid installer identity or size")
    if not re.fullmatch(r"[a-f0-9]{64}", installer["sha256"]):
        raise ValueError("Invalid installer hash")
    if set(payload["protocol"]) != {"host", "worker"} or payload["protocol"] != {"host": 1, "worker": 1}:
        raise ValueError("Unsupported updater protocol")
    if any(type(value) is not int for value in payload["protocol"].values()):
        raise ValueError("Invalid protocol types")
    requirements = payload["requirements"]
    if not isinstance(requirements, list) or len(requirements) != len(set(requirements)):
        raise ValueError("Duplicate or invalid requirements")
    if any(not isinstance(value, str) or not re.fullmatch(r"[a-z][a-z0-9._-]{0,63}", value) for value in requirements):
        raise ValueError("Invalid capability")
    data = payload["data"]
    if set(data) != {"schema", "rollbackProtocol"} or type(data["schema"]) is not int or data["schema"] < 1 or type(data["rollbackProtocol"]) is not int or data["rollbackProtocol"] != 1:
        raise ValueError("Invalid data compatibility")


def sign(payload: dict, private_key_b64: str) -> dict:
    raw = canonical_payload(payload)
    private = Ed25519PrivateKey.from_private_bytes(base64.b64decode(private_key_b64, validate=True))
    return {"formatVersion": FORMAT_VERSION, "payloadBase64": base64.b64encode(raw).decode("ascii"),
            "signatureBase64": base64.b64encode(private.sign(raw)).decode("ascii")}


def verify(envelope: dict, public_keys: list[str]) -> dict:
    if set(envelope) != {"formatVersion", "payloadBase64", "signatureBase64"} or type(envelope["formatVersion"]) is not int or envelope["formatVersion"] != FORMAT_VERSION:
        raise ValueError("Unsupported envelope")
    raw = base64.b64decode(envelope["payloadBase64"], validate=True)
    signature = base64.b64decode(envelope["signatureBase64"], validate=True)
    if len(raw) > MAX_ENVELOPE_BYTES or len(signature) != 64:
        raise ValueError("Invalid envelope size")
    for key in public_keys:
        try:
            Ed25519PublicKey.from_public_bytes(base64.b64decode(key, validate=True)).verify(signature, raw)
            payload = json.loads(raw, object_pairs_hook=_unique_object)
            if canonical_payload(payload) != raw:
                raise ValueError("Noncanonical manifest")
            return payload
        except (ValueError, TypeError):
            raise
        except Exception:
            continue
    raise ValueError("Manifest signature does not match a trusted key")


def _unique_object(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("Duplicate manifest field")
        result[key] = value
    return result


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--installer", type=Path, required=True)
    parser.add_argument("--version", required=True)
    parser.add_argument("--channel", choices=["stable", "beta", "internal"], default="stable")
    parser.add_argument("--schema", type=int, required=True)
    parser.add_argument("--source-commit", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    key = os.environ.get("APPCAST_SIGNING_PRIVATE_KEY", "")
    if not key:
        raise SystemExit("Manifest signing key is required")
    with args.installer.open("rb") as installer:
        digest = hashlib.file_digest(installer, "sha256").hexdigest()
    payload = {"formatVersion": 1, "version": args.version, "channel": args.channel,
               "installer": {"name": args.installer.name, "size": args.installer.stat().st_size, "sha256": digest},
               "requirements": DEFAULT_CAPABILITIES, "protocol": {"host": 1, "worker": 1},
               "data": {"schema": args.schema, "rollbackProtocol": 1},
               "release": {"commit": args.source_commit, "tag": "v" + args.version.split("+")[0]}}
    args.output.write_text(json.dumps(sign(payload, key), sort_keys=True, separators=(",", ":")) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
