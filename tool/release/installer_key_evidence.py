"""Local packaging evidence; not a signature or production release approval."""
import base64
import hashlib
import json
from pathlib import Path

KEY_PAYLOADS = ("data/app.so", "updater/plug_update_client.exe")


def digest(path: Path) -> str:
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def inspect_payload(bundle: Path, csv_keys: str) -> dict[str, str]:
    keys = [key.strip() for key in csv_keys.split(",") if key.strip()]
    if not keys or any(len(base64.b64decode(key, validate=True)) != 32 for key in keys):
        raise ValueError("Expected base64 Ed25519 public keys")
    hashes = {}
    for name in KEY_PAYLOADS:
        payload = bundle / name
        data = payload.read_bytes()
        if any(key.encode("ascii") not in data for key in keys):
            raise RuntimeError(f"{name} is missing AUTO_UPDATE_FEED_PUBLIC_KEY")
        hashes[name] = hashlib.sha256(data).hexdigest()
    return hashes


def record(installer: Path, bundle: Path, csv_keys: str, before: dict[str, str]) -> None:
    after = inspect_payload(bundle, csv_keys)
    if before != after:
        raise RuntimeError("Key-bearing payload changed during installer compilation")
    evidence = {"format": 1, "installerSha256": digest(installer), "payloads": after}
    installer.with_suffix(".keys.json").write_text(json.dumps(evidence, indent=2) + "\n", encoding="utf-8")


def verify(installer: Path, bundle: Path, csv_keys: str) -> None:
    try:
        evidence = json.loads(installer.with_suffix(".keys.json").read_text(encoding="utf-8"))
        if (evidence.get("format") != 1 or evidence.get("installerSha256") != digest(installer)
                or evidence.get("payloads") != inspect_payload(bundle, csv_keys)):
            raise ValueError("Installer/payload evidence mismatch")
    except (OSError, ValueError, TypeError, AttributeError) as error:
        raise RuntimeError("Missing or invalid installer key evidence; rebuild with build_installer.py") from error
