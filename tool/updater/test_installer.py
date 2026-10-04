import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from installer import build_installer


class InstallerContractTests(unittest.TestCase):
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
