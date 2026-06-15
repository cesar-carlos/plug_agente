"""Ed25519 helpers for signing and verifying Plug Agente appcast enclosures.

The canonical payload format must stay byte-identical between this module
and `lib/core/security/appcast_signature_verifier.dart`. See
`buildAppcastEnclosureSignable` on the Dart side for the matching
implementation.

Dependency:

    pip install cryptography>=42.0.0

The signing CLI is intended to run in CI; releases never ship without a
public-key check by the runtime when AUTO_UPDATE_REQUIRE_FEED_SIGNATURE=true.
"""

from __future__ import annotations

import base64
from dataclasses import dataclass

from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ed25519

ED25519_PUBLIC_KEY_BYTES = 32
ED25519_SIGNATURE_BYTES = 64


@dataclass(frozen=True)
class EnclosureSignaturePayload:
    """Inputs that participate in the canonical signable representation.

    Field names and ordering are stable across producers; do not rearrange
    without also updating `buildAppcastEnclosureSignable` in Dart and bumping
    every published signature.
    """

    version: str
    os: str
    sha256: str
    channel: str
    rollout_percentage: int
    asset_url: str
    asset_size: int

    def canonical_bytes(self) -> bytes:
        return canonical_payload(
            version=self.version,
            os=self.os,
            sha256=self.sha256,
            channel=self.channel,
            rollout_percentage=self.rollout_percentage,
            asset_url=self.asset_url,
            asset_size=self.asset_size,
        )


def canonical_payload(
    *,
    version: str,
    os: str,
    sha256: str,
    channel: str,
    rollout_percentage: int,
    asset_url: str,
    asset_size: int,
) -> bytes:
    """Builds the UTF-8 canonical representation used as the Ed25519 message.

    Fields are written one per line as ``key=value\\n`` in lexicographic
    order. The Dart verifier (`buildAppcastEnclosureSignable`) must produce
    byte-identical output for the signature to verify.
    """
    entries = {
        "asset_size": str(asset_size),
        "asset_url": asset_url,
        "channel": channel,
        "os": os,
        "rollout_percentage": str(rollout_percentage),
        "sha256": sha256.lower(),
        "version": version,
    }
    lines = [f"{key}={entries[key]}\n" for key in sorted(entries)]
    return "".join(lines).encode("utf-8")


def generate_keypair() -> tuple[str, str]:
    """Generates a fresh Ed25519 keypair and returns base64-encoded values.

    Returns
    -------
    (private_key_b64, public_key_b64)
        Both encoded with standard base64 (no padding stripped). The private
        key is the raw 32-byte seed; the public key is the raw 32-byte
        compressed point. Keep the private key in a secret store; the public
        key is embedded in releases via ``AUTO_UPDATE_FEED_PUBLIC_KEY``.
    """
    private = ed25519.Ed25519PrivateKey.generate()
    private_bytes = private.private_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PrivateFormat.Raw,
        encryption_algorithm=serialization.NoEncryption(),
    )
    public_bytes = private.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return (
        base64.b64encode(private_bytes).decode("ascii"),
        base64.b64encode(public_bytes).decode("ascii"),
    )


def derive_public_key_b64(private_key_b64: str) -> str:
    """Derives the base64 public key from a base64 Ed25519 private key seed."""
    private_bytes = base64.b64decode(private_key_b64)
    if len(private_bytes) != ED25519_PUBLIC_KEY_BYTES:
        raise ValueError(
            f"Ed25519 private key seed must be {ED25519_PUBLIC_KEY_BYTES} raw bytes "
            f"(got {len(private_bytes)})"
        )
    private = ed25519.Ed25519PrivateKey.from_private_bytes(private_bytes)
    public_bytes = private.public_key().public_bytes(
        encoding=serialization.Encoding.Raw,
        format=serialization.PublicFormat.Raw,
    )
    return base64.b64encode(public_bytes).decode("ascii")


def sign_payload(payload: EnclosureSignaturePayload, private_key_b64: str) -> str:
    """Signs the canonical payload and returns a base64-encoded signature."""
    private_bytes = base64.b64decode(private_key_b64)
    if len(private_bytes) != ED25519_PUBLIC_KEY_BYTES:
        raise ValueError(
            f"Ed25519 private key seed must be {ED25519_PUBLIC_KEY_BYTES} raw bytes"
        )
    private = ed25519.Ed25519PrivateKey.from_private_bytes(private_bytes)
    signature = private.sign(payload.canonical_bytes())
    if len(signature) != ED25519_SIGNATURE_BYTES:
        raise RuntimeError(
            "Ed25519 implementation produced a non-standard signature size; refusing to publish."
        )
    return base64.b64encode(signature).decode("ascii")


def verify_payload(
    payload: EnclosureSignaturePayload,
    signature_b64: str,
    public_key_b64: str,
) -> bool:
    """Verifies a base64 Ed25519 signature against the canonical payload."""
    try:
        public_bytes = base64.b64decode(public_key_b64)
        signature = base64.b64decode(signature_b64)
    except Exception:
        return False
    if (
        len(public_bytes) != ED25519_PUBLIC_KEY_BYTES
        or len(signature) != ED25519_SIGNATURE_BYTES
    ):
        return False
    try:
        public = ed25519.Ed25519PublicKey.from_public_bytes(public_bytes)
        public.verify(signature, payload.canonical_bytes())
        return True
    except Exception:
        return False


def parse_public_keys_csv(raw: str | None) -> list[str]:
    """Splits a comma-separated list of base64 public keys.

    Mirror of ``parseAppcastPublicKeys`` in
    ``lib/core/security/appcast_signature_verifier.dart``.
    Trims whitespace and drops empty entries.
    """
    if not raw:
        return []
    return [entry.strip() for entry in raw.split(",") if entry.strip()]


def verify_with_any_key(
    payload: EnclosureSignaturePayload,
    signature_b64: str,
    public_keys_csv: str,
) -> bool:
    """Returns True when [signature_b64] verifies against any key in the CSV.

    Used by tooling to confirm an item is acceptable to a fleet of clients
    that may run with multiple trusted keys during a rotation window.
    """
    for candidate in parse_public_keys_csv(public_keys_csv):
        if verify_payload(payload, signature_b64, candidate):
            return True
    return False
