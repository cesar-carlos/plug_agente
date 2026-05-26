"""Tests for tool.appcast_signing.

Skipped when the optional `cryptography` dependency is not installed locally.
CI installs it via `pip install cryptography` before running this suite.
"""

from __future__ import annotations

import unittest

try:
    from tool import appcast_signing
except ModuleNotFoundError:  # pragma: no cover - exercised when cryptography is missing
    appcast_signing = None


@unittest.skipIf(appcast_signing is None, "cryptography library not installed locally")
class AppcastSigningTests(unittest.TestCase):
    def test_canonical_payload_is_byte_identical_to_dart(self) -> None:
        # Must match `buildAppcastEnclosureSignable` in
        # lib/core/security/appcast_signature_verifier.dart.
        payload = appcast_signing.canonical_payload(
            version="1.6.9+1",
            os="windows",
            sha256="AABBCC",
            channel="stable",
            rollout_percentage=100,
            asset_url="https://example.com/PlugAgente-Setup-1.6.9.exe",
            asset_size=21173534,
        )
        self.assertEqual(
            payload,
            b"asset_size=21173534\n"
            b"asset_url=https://example.com/PlugAgente-Setup-1.6.9.exe\n"
            b"channel=stable\n"
            b"os=windows\n"
            b"rollout_percentage=100\n"
            b"sha256=aabbcc\n"
            b"version=1.6.9+1\n",
        )

    def test_round_trip_sign_then_verify(self) -> None:
        private_b64, public_b64 = appcast_signing.generate_keypair()
        payload = appcast_signing.EnclosureSignaturePayload(
            version="1.6.9+1",
            os="windows",
            sha256="aabb",
            channel="stable",
            rollout_percentage=100,
            asset_url="https://example.com/setup.exe",
            asset_size=42,
        )

        signature = appcast_signing.sign_payload(payload, private_b64)

        self.assertTrue(appcast_signing.verify_payload(payload, signature, public_b64))

    def test_verify_rejects_tampered_payload(self) -> None:
        private_b64, public_b64 = appcast_signing.generate_keypair()
        payload = appcast_signing.EnclosureSignaturePayload(
            version="1.6.9+1",
            os="windows",
            sha256="aabb",
            channel="stable",
            rollout_percentage=100,
            asset_url="https://example.com/setup.exe",
            asset_size=42,
        )

        signature = appcast_signing.sign_payload(payload, private_b64)

        tampered = appcast_signing.EnclosureSignaturePayload(
            version="2.0.0+1",  # changed
            os="windows",
            sha256="aabb",
            channel="stable",
            rollout_percentage=100,
            asset_url="https://example.com/setup.exe",
            asset_size=42,
        )
        self.assertFalse(appcast_signing.verify_payload(tampered, signature, public_b64))

    def test_verify_rejects_other_key(self) -> None:
        private_b64, _ = appcast_signing.generate_keypair()
        _, other_public_b64 = appcast_signing.generate_keypair()
        payload = appcast_signing.EnclosureSignaturePayload(
            version="1.6.9+1",
            os="windows",
            sha256="aabb",
            channel="stable",
            rollout_percentage=100,
            asset_url="https://example.com/setup.exe",
            asset_size=42,
        )

        signature = appcast_signing.sign_payload(payload, private_b64)

        self.assertFalse(appcast_signing.verify_payload(payload, signature, other_public_b64))

    def test_verify_rejects_corrupt_signature(self) -> None:
        _, public_b64 = appcast_signing.generate_keypair()
        payload = appcast_signing.EnclosureSignaturePayload(
            version="1.6.9+1",
            os="windows",
            sha256="aabb",
            channel="stable",
            rollout_percentage=100,
            asset_url="https://example.com/setup.exe",
            asset_size=42,
        )

        self.assertFalse(appcast_signing.verify_payload(payload, "garbage", public_b64))

    def test_derive_public_key_matches_keypair(self) -> None:
        private_b64, public_b64 = appcast_signing.generate_keypair()
        self.assertEqual(appcast_signing.derive_public_key_b64(private_b64), public_b64)


if __name__ == "__main__":
    unittest.main()
