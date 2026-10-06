import datetime
import hashlib
import os
from pathlib import Path
import shutil
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from installer import build_installer as build
from installer import signpath_staging as staging
from tool.release import windows_version_info as metadata


class SigningPayloadTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.original = self.root / "original.exe"
        self.signed = self.root / "signed.exe"
        data = bytearray(1024)
        data[:2] = b"MZ"
        struct.pack_into("<I", data, 0x3C, 128)
        data[128:132] = b"PE\0\0"
        struct.pack_into("<H", data, 152, 0x20B)
        data[700:708] = b"app-code"
        self.original.write_bytes(data)
        result = data + bytearray(b"signature".ljust(64, b"\0"))
        struct.pack_into("<I", result, 216, 1234)
        struct.pack_into("<II", result, 296, 1024, 64)
        self.signed.write_bytes(result)

    def test_authenticode_only_changes_are_accepted(self):
        staging.require_unchanged_payload(self.original, self.signed)

    def test_signed_code_replacement_is_rejected(self):
        data = bytearray(self.signed.read_bytes())
        data[700] ^= 1
        self.signed.write_bytes(data)
        with self.assertRaisesRegex(ValueError, "changed executable content"):
            staging.require_unchanged_payload(self.original, self.signed)

    def test_missing_truncated_and_displaced_signature_are_rejected(self):
        valid = self.signed.read_bytes()
        for offset, size in ((0, 0), (1024, 128), (900, 188)):
            data = bytearray(valid)
            struct.pack_into("<II", data, 296, offset, size)
            self.signed.write_bytes(data)
            with self.subTest(offset=offset), self.assertRaisesRegex(ValueError, "Invalid appended"):
                staging.require_unchanged_payload(self.original, self.signed)

    def test_windows_version_bounds_are_checked(self):
        for version in ("1.2.3", "1.2.3+65536", "1.2.3+1 /bad", "-1.2.3+1"):
            with self.subTest(version=version), self.assertRaises(ValueError):
                metadata.version_resource(version, "helper.exe")


@unittest.skipUnless(os.name == "nt", "Windows resource and Inno signing integration")
class StagedInstallerTests(unittest.TestCase):
    def test_stages_signs_and_reuses_the_inno_uninstaller_without_changing_dart_payload(self):
        from cryptography import x509
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        from cryptography.hazmat.primitives.serialization import pkcs12
        from cryptography.x509.oid import NameOID, ExtendedKeyUsageOID

        dart = shutil.which("dart")
        signtool = build.find_signtool()
        try:
            iscc = build.find_iscc()
        except SystemExit as error:
            self.skipTest(str(error))
        if not dart or not signtool:
            self.skipTest("Dart and Windows SDK are required")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            installer = root / "installer"
            installer.mkdir()
            bundle = root / "bundle"
            bundle.mkdir()
            dist = installer / "dist"
            dist.mkdir()
            stage = installer / "signpath-work"
            script = root / "probe.dart"
            script.write_text("void main() { print('Dart payload preserved'); }", encoding="utf-8")
            executable = root / "probe.exe"
            subprocess.run(build.resolve_command([dart, "compile", "exe", str(script), "-o", str(executable)]),
                           capture_output=True, check=True, timeout=90)
            for name in build.PROJECT_EXECUTABLES:
                destination = bundle / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(executable, destination)
                before = metadata.executable_overlay(destination.read_bytes())
                metadata.set_version_info(destination, "1.2.3+4")
                self.assertEqual(before, metadata.executable_overlay(destination.read_bytes()))
                self.assertEqual(metadata.read_version_info(destination)["ProductVersion"], "1.2.3+4")
            probe = subprocess.run([str(bundle / "plug_agente_elevated_runner.exe"), "--help"],
                                   capture_output=True, text=True, check=True, timeout=15)
            self.assertIn("Dart payload preserved", probe.stdout)
            (root / "pubspec.yaml").write_text("version: 1.2.3+4\n")
            (root / "readme.md").write_text("## Privacy policy\nTest notice.\n")
            (root / "LICENSE").write_text("MIT test fixture")
            icon = root / "windows/runner/resources/app_icon.ico"
            icon.parent.mkdir(parents=True)
            icon.write_bytes(b"configuration fixture")
            setup = installer / "setup.iss"
            setup.write_text(f'''#define MyAppVersion "1.2.3"
[Setup]
AppName=Plug Agente
AppVersion={{#MyAppVersion}}
DefaultDirName={{autopf}}\\PlugAgenteTest
OutputDir={dist}
OutputBaseFilename=PlugAgente-Setup-1.2.3
VersionInfoProductName=Plug Agente
VersionInfoProductTextVersion={{#MyAppWorkerVersion}}
SignedUninstaller=yes
SignedUninstallerDir={{#ExternalSignedUninstallerDir}}
InfoBeforeFile={{#PrivacyNoticeFile}}
[Files]
Source: "{bundle}\\plug_agente.exe"; DestDir: "{{app}}"
''', encoding="utf-8")
            key = rsa.generate_private_key(public_exponent=65537, key_size=2048)
            name = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, "Disposable installer test")])
            now = datetime.datetime.now(datetime.timezone.utc)
            certificate = (x509.CertificateBuilder().subject_name(name).issuer_name(name).public_key(key.public_key())
                           .serial_number(x509.random_serial_number()).not_valid_before(now - datetime.timedelta(days=1))
                           .not_valid_after(now + datetime.timedelta(days=1))
                           .add_extension(x509.ExtendedKeyUsage([ExtendedKeyUsageOID.CODE_SIGNING]), False)
                           .sign(key, hashes.SHA256()))
            pfx = root / "test.pfx"
            pfx.write_bytes(pkcs12.serialize_key_and_certificates(b"test", key, certificate, None, serialization.NoEncryption()))

            def sign(path):
                subprocess.run([signtool, "sign", "/f", str(pfx), "/fd", "SHA256", str(path)],
                               capture_output=True, check=True, timeout=30)

            changes = {"PROJECT_ROOT": root, "INSTALLER_DIR": installer, "BUILD_DIR": bundle,
                       "SETUP_ISS": setup, "DIST_DIR": dist}
            with patch.multiple(build, **changes), patch.object(metadata, "PROJECT_ROOT", root), \
                    patch.object(staging, "STAGE", stage), patch.object(build, "find_iscc", return_value=iscc), \
                    patch.object(build, "resolve_auto_update_define", return_value="stable"):
                staging.prepare()
                signed = stage / "signed-components"
                shutil.copytree(stage / "unsigned-components", signed)
                for path in signed.rglob("*.exe"):
                    sign(path)
                with self.assertRaises(subprocess.CalledProcessError):
                    staging.signature_thumbprint(signed / "plug_agente.exe")
                # A disposable self-signed certificate is never added to a trust store.
                # Mock only trust-chain verification, exercising real PE signing and ISCC reuse.
                thumbprint = certificate.fingerprint(hashes.SHA1()).hex().upper()
                with patch.object(build, "verify_signed_file"), patch.object(staging, "signature_thumbprint", return_value=thumbprint):
                    staging.package(signed)
                    final = stage / "final.exe"
                    shutil.copy2(stage / "unsigned-installer/PlugAgente-Setup-1.2.3.exe", final)
                    sign(final)
                    staging.finalize(final)
                    self.assertEqual(hashlib.sha256(final.read_bytes()).digest(),
                                     hashlib.sha256((dist / "PlugAgente-Setup-1.2.3.exe").read_bytes()).digest())


if __name__ == "__main__":
    unittest.main()
