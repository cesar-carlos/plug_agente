import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from tool.appcast.appcast_signing import generate_keypair
from tool.updater.manifest import DEFAULT_CAPABILITIES, sign
from tool.updater.verify_release import verify_release


class VerifyReleaseTests(unittest.TestCase):
    def test_release_asset_identity_and_bytes_must_match_signed_manifest(self):
        private, public = generate_keypair()
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            installer = root / 'PlugAgente-Setup-1.8.6.exe'
            installer.write_bytes(b'fixture executable')
            payload = {'formatVersion': 1, 'version': '1.8.6+1', 'channel': 'beta',
                       'installer': {'name': installer.name, 'size': installer.stat().st_size,
                                     'sha256': hashlib.sha256(installer.read_bytes()).hexdigest()},
                       'requirements': DEFAULT_CAPABILITIES, 'protocol': {'host': 1, 'worker': 1},
                       'data': {'schema': 30, 'rollbackProtocol': 1},
                       'release': {'commit': 'b' * 40, 'tag': 'v1.8.6'}}
            manifest = root / 'manifest.json'
            manifest.write_text(json.dumps(sign(payload, private)), encoding='utf-8')
            self.assertEqual(verify_release(manifest, installer, public, '1.8.6+1', 'beta'), payload)
            with self.assertRaises(ValueError):
                verify_release(manifest, installer, public, '1.8.6+1', 'stable')
            with self.assertRaises(ValueError):
                verify_release(manifest, installer, public, '1.8.6+1', 'beta', 'c' * 40)
            installer.write_bytes(b'tampered executable')
            with self.assertRaises(ValueError):
                verify_release(manifest, installer, public, '1.8.6+1', 'beta')
