import base64
import os
import json
import tempfile
import unittest
from types import SimpleNamespace
from pathlib import Path
from unittest.mock import patch

from installer import build_installer


class InstallerContractTests(unittest.TestCase):
    def test_manifest_only_requires_keys_before_build(self):
        args = SimpleNamespace(manifest_only=True, prepare_signpath=False, sync_version=False)
        with patch.dict(os.environ, {}, clear=True), patch.object(build_installer, "parse_args", return_value=args), \
                patch.object(build_installer, "signing_cert_path", return_value=None), \
                patch.object(build_installer, "configure_native_feed_keys", return_value=None), \
                patch.object(build_installer, "run") as run:
            with self.assertRaisesRegex(SystemExit, "Ed25519"):
                build_installer.main()
            run.assert_not_called()
            self.assertEqual(os.environ["AUTO_UPDATE_REQUIRE_VALID_SIGNATURE"], "false")
            self.assertEqual(os.environ["AUTO_UPDATE_REQUIRE_FEED_SIGNATURE"], "true")
            self.assertEqual(os.environ["WINDOWS_CODE_SIGNING_REQUIRED"], "false")

    def test_manifest_only_cannot_mix_signing_providers(self):
        for signpath, certificate in [(True, None), (False, Path("fixture.pfx"))]:
            args = SimpleNamespace(manifest_only=True, prepare_signpath=signpath, sync_version=False)
            with self.subTest(signpath=signpath), patch.object(build_installer, "parse_args", return_value=args), \
                    patch.object(build_installer, "signing_cert_path", return_value=certificate), \
                    patch.object(build_installer, "run") as run:
                with self.assertRaisesRegex(SystemExit, "cannot use SignPath or a local"):
                    build_installer.main()
                run.assert_not_called()

    def test_packaging_rejects_missing_font_registration_and_stale_font_assets(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            assets = root / "bundle/data/flutter_assets"
            assets.mkdir(parents=True)
            names = [f"assets/fonts/montserrat/{name}" for name in ("Montserrat.ttf", "Montserrat-Italic.ttf")]
            for name in names:
                source = root / name
                bundled = assets / name
                source.parent.mkdir(parents=True, exist_ok=True)
                bundled.parent.mkdir(parents=True, exist_ok=True)
                source.write_bytes(b"font source")
                bundled.write_bytes(b"font source")
            manifest = assets / "FontManifest.json"
            with patch.object(build_installer, "PROJECT_ROOT", root), patch.object(build_installer, "BUILD_DIR", root / "bundle"):
                manifest.write_text("[]")
                with self.assertRaisesRegex(SystemExit, "flutter.fonts"):
                    build_installer.verify_bundled_fonts()
                manifest.write_text(json.dumps([{"family": "Montserrat", "fonts": [{"asset": name} for name in names]}]))
                build_installer.verify_bundled_fonts()
                (assets / names[1]).write_bytes(b"stale font")
                with self.assertRaisesRegex(SystemExit, "stale"):
                    build_installer.verify_bundled_fonts()

    def test_signed_build_without_feed_keys_fails_before_compilation(self):
        with patch.object(build_installer, "resolve_auto_update_define", return_value=None), patch.object(
            build_installer, "should_sign_artifacts", return_value=True
        ):
            with self.assertRaisesRegex(SystemExit, "feed_keys_unavailable"):
                build_installer.configure_native_feed_keys()

    def test_unsigned_development_build_can_omit_feed_keys(self):
        with patch.object(build_installer, "resolve_auto_update_define", return_value=None), patch.object(
            build_installer, "should_sign_artifacts", return_value=False
        ):
            self.assertIsNone(build_installer.configure_native_feed_keys())

    def test_feed_keys_from_dotenv_reach_the_native_build_environment(self):
        first = base64.b64encode(bytes(range(32))).decode("ascii")
        second = base64.b64encode(bytes(reversed(range(32)))).decode("ascii")
        with tempfile.TemporaryDirectory() as temporary, patch.dict(os.environ, {}, clear=True):
            env_file = Path(temporary) / ".env"
            env_file.write_text(f'AUTO_UPDATE_FEED_PUBLIC_KEY="{first}, {second}"\n')
            with patch.object(build_installer, "ENV_FILE", env_file):
                keys = build_installer.configure_native_feed_keys()
                self.assertEqual(keys, f"{first},{second}")
                self.assertEqual(os.environ["AUTO_UPDATE_FEED_PUBLIC_KEY"], keys)

    def test_invalid_feed_keys_are_rejected(self):
        valid = base64.b64encode(bytes(range(32))).decode("ascii")
        for value in ("not-base64", "YWJj", f"{valid},", f",{valid}"):
            with self.subTest(value=value), patch.object(
                build_installer, "resolve_auto_update_define", return_value=value
            ):
                with self.assertRaisesRegex(SystemExit, "AUTO_UPDATE_FEED_PUBLIC_KEY"):
                    build_installer.configure_native_feed_keys()

    def test_packaging_rejects_a_native_client_built_without_configured_keys(self):
        keys = base64.b64encode(bytes(range(32))).decode("ascii")
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "updater").mkdir()
            client = root / "updater" / "plug_update_client.exe"
            with patch.object(build_installer, "BUILD_DIR", root):
                for contents in (None, b"native client without keys", b"different-key\0"):
                    if contents is not None:
                        client.write_bytes(contents)
                    with self.subTest(contents=contents), self.assertRaisesRegex(SystemExit, "Native updater"):
                        build_installer.verify_native_feed_keys(keys)
                client.write_bytes(b"native client\0" + keys.encode("ascii") + b"\0")
                build_installer.verify_native_feed_keys(keys)

    def test_packaging_requires_runtime_dlls_even_when_the_machine_has_visual_cpp(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            with patch.object(build_installer, "BUILD_DIR", root):
                with self.assertRaisesRegex(SystemExit, "msvcp140.dll.*vcruntime140.dll"):
                    build_installer.verify_bundled_vc_runtime()

    def test_packaging_accepts_a_complete_app_local_runtime(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in build_installer.REQUIRED_VC_RUNTIME_DLLS:
                (root / name).write_bytes(b"runtime")
            with patch.object(build_installer, "BUILD_DIR", root):
                build_installer.verify_bundled_vc_runtime()

    def test_packaging_rejects_an_empty_runtime_dll(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in build_installer.REQUIRED_VC_RUNTIME_DLLS:
                (root / name).write_bytes(b"runtime")
            (root / "vcruntime140.dll").write_bytes(b"")
            with patch.object(build_installer, "BUILD_DIR", root):
                with self.assertRaisesRegex(SystemExit, "vcruntime140.dll"):
                    build_installer.verify_bundled_vc_runtime()

    def test_exact_expected_asset_is_required_even_when_other_installers_exist(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            setup = root / "setup.iss"
            setup.write_text('#define MyAppVersion "1.8.6"\n')
            (root / "PlugAgente-Setup-9.0.0.exe").write_bytes(b"wrong")
            with patch.object(build_installer, "DIST_DIR", root), patch.object(build_installer, "SETUP_ISS", setup):
                with self.assertRaises(SystemExit):
                    build_installer.find_generated_installer()
                expected = root / "PlugAgente-Setup-1.8.6.exe"
                expected.write_bytes(b"expected")
                self.assertEqual(build_installer.find_generated_installer(), expected)

    def test_channel_is_compiled_into_installer_without_shell_arguments(self):
        with patch.object(build_installer, "find_iscc", return_value="ISCC"), patch.object(build_installer, "build_iscc_signtool_command", return_value=None):
            with patch.object(build_installer, "resolve_auto_update_define", return_value="beta"):
                command = build_installer.build_iscc_command()
                self.assertIn("/DMyAppChannel=beta", command)
                self.assertTrue(any(argument.startswith('/DMyAppWorkerVersion=') and '+' in argument for argument in command))
            with patch.object(build_installer, "resolve_auto_update_define", return_value="stable /CURRENTUSER"):
                with self.assertRaises(SystemExit):
                    build_installer.build_iscc_command()
