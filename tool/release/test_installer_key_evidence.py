import base64
import tempfile
import unittest
from pathlib import Path
from tool.release.installer_key_evidence import KEY_PAYLOADS, inspect_payload, record, verify


class InstallerKeyEvidenceTests(unittest.TestCase):
    def test_rotation_checks_both_payloads_and_detects_changes_during_packaging(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            keys = [base64.b64encode(bytes([value]) * 32).decode() for value in (1, 2)]
            csv = ",".join(keys)
            installer = root / "setup.exe"
            installer.write_bytes(b"compressed bytes")
            for name in KEY_PAYLOADS:
                path = root / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_bytes(csv.encode())
            before = inspect_payload(root, csv)
            record(installer, root, csv, before)
            verify(installer, root, csv)
            (root / KEY_PAYLOADS[0]).write_bytes(csv.encode() + b"changed")
            with self.assertRaisesRegex(RuntimeError, "evidence"):
                verify(installer, root, csv)
            with self.assertRaisesRegex(RuntimeError, "changed during"):
                record(installer, root, csv, before)
            (root / KEY_PAYLOADS[0]).write_bytes(keys[0].encode())
            with self.assertRaisesRegex(RuntimeError, "missing AUTO_UPDATE"):
                inspect_payload(root, csv)

    def test_rejects_invalid_key(self):
        with self.assertRaises(ValueError):
            inspect_payload(Path("unused"), "bm90LWEtMzItYnl0ZS1rZXk=")
