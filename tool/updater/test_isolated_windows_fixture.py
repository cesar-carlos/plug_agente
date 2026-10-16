from pathlib import Path
import tempfile
import unittest

from tool.updater.isolated_windows_fixture import PROJECT, require_identity, rewrite_installer, rewrite_native, assert_isolated_sources


class IsolatedWindowsFixtureTests(unittest.TestCase):
    identity = "PlugAgenteHomologacao_0123456789ab"

    def test_operational_or_arbitrary_identity_is_refused(self):
        for name in ("PlugAgente", "PlugAgenteUpdater", "test", "PlugAgenteHomologacao_../escape"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                require_identity(name)

    def test_derived_sources_isolate_all_os_identities_without_enabling_application(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            native = root / "windows/updater"
            native.mkdir(parents=True)
            installer = root / "installer"
            installer.mkdir()
            for path in (PROJECT / "windows/updater").iterdir():
                if path.suffix in {".cpp", ".h"}:
                    (native / path.name).write_text(rewrite_native(path.read_text(encoding="utf-8-sig"), self.identity), encoding="utf-8")
            for path in (PROJECT / "installer").glob("*.iss"):
                rewritten = rewrite_installer(path.read_text(encoding="utf-8-sig"), self.identity,
                                              "6C0BBE37-6E1E-44B1-A576-4A86C99939BD", root / "payload")
                (installer / path.name).write_text(rewritten, encoding="utf-8")
            assert_isolated_sources(root, self.identity)
            service = (native / "service_main.cpp").read_text(encoding="utf-8")
            self.assertIn(self.identity + "Updater.v1", service)
            self.assertIn("transition_validation_required", service)
            self.assertIn("authorize_client(pipe, policy)", service)
            setup = (installer / "setup.iss").read_text(encoding="utf-8")
            self.assertIn("{commonappdata}\\" + self.identity, setup)
            self.assertIn("{commonappdata}\\" + self.identity + "Updater\\policy.json", setup)
            self.assertNotIn(self.identity + "Homologacao_", setup)
            self.assertIn("/REPAIR=optional", (installer / "installation_repair.iss").read_text(encoding="utf-8"))
            contract = native / "contract.h"
            contract.write_text(contract.read_text(encoding="utf-8").replace("kApplicationContractImplemented = false", "kApplicationContractImplemented = true"), encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "activation gate"):
                assert_isolated_sources(root, self.identity)

    def test_residual_operational_identity_prevents_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "installer").mkdir()
            (root / "installer/setup.iss").write_text('Root: HKA; Subkey: "Software\\Classes\\plugdb";', encoding="utf-8")
            with self.assertRaisesRegex(RuntimeError, "Operational identity"):
                assert_isolated_sources(root, self.identity)
