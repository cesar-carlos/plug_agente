import base64
import copy
import unittest
import json
from pathlib import Path

from tool.appcast.appcast_signing import generate_keypair
from tool.updater import manifest
from tool.appcast.appcast_manager import ManifestBindingPayload
from tool.appcast.appcast_signing import EnclosureSignaturePayload, verify_with_any_key


class ManifestTests(unittest.TestCase):
    def test_shared_manifest_and_feed_binding_fixture(self):
        fixture = json.loads((Path(__file__).resolve().parents[2] / 'test/fixtures/updater_manifest_v1.json').read_text(encoding='utf-8'))
        self.assertEqual(manifest.verify(fixture['envelope'], [fixture['publicKey']]), fixture['payload'])
        enclosure = EnclosureSignaturePayload(version='1.8.6+1', os='windows', sha256='a'*64,
            channel='stable', rollout_percentage=5, asset_url='https://example.com/PlugAgente-Setup-1.8.6.exe', asset_size=123)
        entry = fixture['feedBinding']
        binding = ManifestBindingPayload(enclosure, entry['url'], entry['sha256'])
        self.assertEqual(binding.canonical_bytes().decode(), entry['payload'])
        self.assertTrue(verify_with_any_key(binding, entry['signature'], fixture['publicKey']))

    def setUp(self):
        self.private, self.public = generate_keypair()
        self.payload = {"formatVersion": 1, "version": "1.8.6+1", "channel": "stable",
                        "installer": {"name": "PlugAgente-Setup-1.8.6.exe", "size": 123, "sha256": "a" * 64},
                        "requirements": manifest.DEFAULT_CAPABILITIES,
                        "protocol": {"host": 1, "worker": 1}, "data": {"schema": 30, "rollbackProtocol": 1},
                        "release": {"commit": "b" * 40, "tag": "v1.8.6"}}

    def test_signed_round_trip_and_key_rotation(self):
        _, old = generate_keypair()
        self.assertEqual(manifest.verify(manifest.sign(self.payload, self.private), [old, self.public]), self.payload)

    def test_boolean_or_float_protocol_versions_are_not_integers(self):
        for value in [True, 1.0]:
            changed = copy.deepcopy(self.payload)
            changed["protocol"]["host"] = value
            with self.assertRaises(ValueError):
                manifest.sign(changed, self.private)
            changed = copy.deepcopy(self.payload)
            changed["formatVersion"] = value
            with self.assertRaises(ValueError):
                manifest.sign(changed, self.private)

    def test_tampering_including_permissions_is_rejected(self):
        envelope = manifest.sign(self.payload, self.private)
        changed = copy.deepcopy(self.payload)
        changed["requirements"] = ["firewall.new"]
        envelope["payloadBase64"] = base64.b64encode(manifest.canonical_payload(changed)).decode()
        with self.assertRaises(ValueError):
            manifest.verify(envelope, [self.public])

    def test_unsigned_and_unknown_protocol_are_rejected(self):
        with self.assertRaises(ValueError):
            manifest.verify({}, [self.public])
        self.payload["protocol"]["host"] = 2
        with self.assertRaises(ValueError):
            manifest.sign(self.payload, self.private)

    def test_installer_path_injection_and_duplicates_are_rejected(self):
        self.payload["installer"]["name"] = "../setup.exe"
        with self.assertRaises(ValueError):
            manifest.sign(self.payload, self.private)
        self.payload["installer"]["name"] = "PlugAgente-Setup-1.8.6.exe"
        self.payload["requirements"] = ["app.files", "app.files"]
        with self.assertRaises(ValueError):
            manifest.sign(self.payload, self.private)
