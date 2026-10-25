import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

from tool.updater import application_source as source
from tool.updater import application_build_proof as proof
from tool.updater import application_package_binding as binding
from tool.updater import isolated_windows_fixture as fixtures
from tool.updater import isolated_runtime as runtime
from tool.updater import bootstrap_fixture_input as bootstrap
from tool.updater import build_isolated_application as builds
from tool.updater.isolated_windows_fixture import PROJECT
from tool.updater.lifecycle_payload import REQUIRED_PAYLOAD_FILES


def archive(entries):
    stream = io.BytesIO()
    with tarfile.open(fileobj=stream, mode="w") as output:
        for name, content, linked in entries:
            item = tarfile.TarInfo(name)
            if linked:
                item.type = tarfile.SYMTYPE
                item.linkname = "../outside"
                output.addfile(item)
            else:
                item.size = len(content)
                output.addfile(item, io.BytesIO(content))
    return stream.getvalue()


class ApplicationSourceTests(unittest.TestCase):
    identity = "PlugAgenteHomologacao_0123456789ab"

    def test_paths_refuse_traversal_streams_absolute_names_and_git_metadata(self):
        for name in ("../file", "/file", "C:/file", "a//b", "a/./b", ".git/config", "a\\b", "", "x\nname"):
            with self.subTest(name=name), self.assertRaises(RuntimeError):
                source.relative_name(name)
        self.assertEqual(source.relative_name("lib/main.dart"), "lib/main.dart")

    def test_archive_reconstructs_exact_ps1_git_blob_without_accepting_changed_content(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            original = b"Write-Output 'fixture'\n"
            files = {"tool/test.ps1": source.blob_hash(original)}
            source.export_archive(archive([("tool/test.ps1", original.replace(b"\n", b"\r\n"), False)]), root, files)
            self.assertEqual((root / "tool/test.ps1").read_bytes(), original)
            with self.assertRaisesRegex(RuntimeError, "differs"):
                source.export_archive(archive([("tool/test.ps1", b"changed\r\n", False)]), root, files)

    def test_linked_unexpected_missing_and_corrupted_archive_entries_are_refused(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            files = {"file": source.blob_hash(b"expected")}
            for entries in ([("file", b"", True)], [("../file", b"expected", False)],
                            [("file", b"changed", False)], [("extra", b"expected", False)], []):
                with self.subTest(entries=len(entries)), self.assertRaises(RuntimeError):
                    source.export_archive(archive(entries), root, files)

    def test_native_derivation_isolates_mutex_window_control_and_restart(self):
        original = (PROJECT / "windows/runner/main.cpp").read_bytes()
        changed = source.derived_bytes("windows/runner/main.cpp", original, self.identity).decode()
        self.assertNotIn("PlugAgente_SingleInstance", changed)
        self.assertNotIn('L"PlugAgenteUpdater"', changed)
        self.assertNotIn("FLUTTER_RUNNER_WIN32_WINDOW", changed)
        self.assertNotIn("if (!is_installation_check && !is_update_validation) RegisterCrashRestart();", changed)
        self.assertIn(self.identity + "_WINDOW", changed)
        self.assertLess(changed.index('GetEnvironmentVariableW(L"PLUG_AGENT_BOOTSTRAP_ROOT"'), changed.index("PWSTR program_files"))
        self.assertLess(changed.index('GetEnvironmentVariableW(L"PLUG_AGENT_BOOTSTRAP_ROOT"'), changed.index("const auto setup_guard"))
        window = source.derived_bytes("windows/runner/win32_window.cpp", (PROJECT / "windows/runner/win32_window.cpp").read_bytes(), self.identity)
        self.assertIn((self.identity + "_WINDOW").encode(), window)
        with self.assertRaisesRegex(RuntimeError, "Unsupported native"):
            source.derived_bytes("windows/runner/main.cpp", b"unreviewed runner", self.identity)

    def test_installation_check_uses_real_bundle_check_before_private_bootstrap(self):
        original = (PROJECT / source.ENTRYPOINT).read_bytes()
        changed = source.derived_bytes(source.ENTRYPOINT, original, self.identity).decode()
        self.assertIn("checkInstallationBundle(rootBundle)", changed)
        self.assertLess(changed.index("args.contains('--installation-check')"), changed.index("PLUG_AGENT_BOOTSTRAP_ROOT"))
        native = source.derived_bytes("windows/runner/main.cpp", (PROJECT / "windows/runner/main.cpp").read_bytes(), self.identity).decode()
        self.assertIn('if (!is_installation_check && GetEnvironmentVariableW', native)
        self.assertLess(native.index("const bool is_installation_check"), native.index('GetEnvironmentVariableW(L"PLUG_AGENT_BOOTSTRAP_ROOT"'))

    def test_helper_mutex_and_installer_restart_manager_are_isolated(self):
        original = (PROJECT / "windows/update_helper/main.cpp").read_bytes()
        changed = source.derived_bytes("windows/update_helper/main.cpp", original, self.identity)
        self.assertNotIn(b"PlugAgenteUpdateHelper", changed)
        self.assertIn((self.identity + "UpdateHelper").encode(), changed)
        installer = fixtures.rewrite_installer("CloseApplications=yes", self.identity,
                                               "11111111-1111-4111-8111-111111111111", PROJECT)
        self.assertEqual(installer, "CloseApplications=no")

    def test_original_git_bytes_cannot_bypass_required_native_derivation(self):
        name = "windows/update_helper/main.cpp"
        original = b'CreateMutexW(nullptr, FALSE, L"Global\\\\PlugAgenteUpdateHelper");'
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            target = root / name
            target.parent.mkdir(parents=True)
            target.write_bytes(original)
            (root / ".env").write_bytes(source.SAFE_ENV)
            expected = {name: hashlib.sha256(original).hexdigest(),
                        ".env": hashlib.sha256(source.SAFE_ENV).hexdigest()}
            with patch.object(proof, "git_files", return_value={name: source.blob_hash(original)}), \
                    patch.object(proof, "git_output", return_value=original):
                with self.assertRaisesRegex(RuntimeError, "derivation"):
                    proof.verify_sources(root, "a" * 40, self.identity, expected)

    def test_environment_preserves_toolchain_only(self):
        self.assertEqual(source.tool_environment({"PATH": "toolchain", "SYSTEMDRIVE": "C:", "NODE_OPTIONS": "private", "JWT_ACCESS_SECRET": "private", "DATABASE_URL": "private", "PYTHONPATH": "private"}), {"PATH": "toolchain", "SYSTEMDRIVE": "C:"})

    def test_implicit_revisions_fail_before_git(self):
        with patch.object(source, "git_output", side_effect=AssertionError("Git must not run")):
            for revision in ("HEAD", "main", "a" * 39, "--help"):
                with self.subTest(revision=revision), self.assertRaisesRegex(RuntimeError, "explicit full"):
                    source.git_files(revision)

    def test_source_mutation_is_refused_by_the_captured_and_git_inventories(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "pubspec.lock").write_bytes(b"locked")
            (root / ".env").write_bytes(source.SAFE_ENV)
            expected = {"pubspec.lock": hashlib.sha256(b"locked").hexdigest(), ".env": hashlib.sha256(source.SAFE_ENV).hexdigest()}
            with patch.object(proof, "git_files", return_value={"pubspec.lock": source.blob_hash(b"locked")}):
                proof.verify_sources(root, "a" * 40, self.identity, expected)
                (root / "pubspec.lock").write_bytes(b"changed lock")
                with self.assertRaisesRegex(RuntimeError, "source changed"):
                    proof.verify_sources(root, "a" * 40, self.identity, expected)

    def test_unreviewed_bootstrap_and_enabled_production_gate_are_refused(self):
        revision = "a" * 40
        bootstrap = b"reviewed bootstrap"
        tree = b"100644 blob " + b"b" * 40 + b"\t" + source.ENTRYPOINT.encode() + b"\0"
        def git(*arguments):
            if arguments[0] == "cat-file":
                return b"commit"
            if arguments[0] == "merge-base":
                return b""
            if arguments[0] == "ls-tree":
                return tree
            if arguments[-1].endswith(source.ENTRYPOINT):
                return bootstrap
            return b"constexpr bool kApplicationContractImplemented = true;"
        with patch.object(source, "git_output", side_effect=git):
            with self.assertRaisesRegex(RuntimeError, "Bootstrap contract changed"):
                source.git_files(revision)
            with patch.object(source, "SUPPORTED_BOOTSTRAP_SHA256", hashlib.sha256(bootstrap).hexdigest()):
                with self.assertRaisesRegex(RuntimeError, "disabled production gate"):
                    source.git_files(revision)

    def test_build_receipt_rechecks_sources_and_payload_instead_of_trusting_hash_claims(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            path = root / "application-build.json"
            sources = {"source": "a" * 64}
            payload = {name: "b" * 64 for name in REQUIRED_PAYLOAD_FILES}
            state = {"format": 1, "scope": "source-qualified-isolated-bootstrap",
                     "productionActivationGate": False, "entrypoint": source.ENTRYPOINT,
                     "root": str(root), "identity": self.identity, "sourceRoot": str(root / "source"),
                     "revision": "c" * 40, "sourceFiles": sources,
                     "sourceTreeSha256": proof.canonical_hash(sources), "payloadFiles": payload,
                     "payloadTreeSha256": proof.payload_tree_hash(payload)}
            path.write_text(json.dumps(state))
            with patch.object(proof, "require_fixture_root", return_value=root), \
                 patch.object(proof, "require_fixture_artifact", return_value=path), \
                 patch.object(proof, "source_root", return_value=root / "source"), \
                 patch.object(proof, "verify_sources") as verify, \
                 patch.object(proof, "capture_payload", return_value=payload) as capture:
                self.assertEqual(proof.load_application_build(path)["revision"], "c" * 40)
                verify.assert_called_once_with(root / "source", "c" * 40, self.identity, sources)
                state["runtimeInput"] = {"path": str(root / "runtime.json")}
                path.write_text(json.dumps(state))
                with patch.object(runtime, "verify_runtime_reference") as runtime_check, \
                     patch.object(runtime, "load_runtime", return_value={"files": {"msvcp140.dll": {"sha256": "f" * 64}}}):
                    with self.assertRaisesRegex(RuntimeError, "verified private runtime"):
                        proof.load_application_build(path)
                    runtime_check.assert_called_once_with(state["runtimeInput"], root)
                del state["runtimeInput"]
                path.write_text(json.dumps(state))
                capture.return_value = {**payload, "extra.dll": "d" * 64}
                with self.assertRaisesRegex(RuntimeError, "payload changed"):
                    proof.load_application_build(path)
                capture.return_value = payload
                verify.side_effect = RuntimeError("Application source changed after capture")
                with self.assertRaisesRegex(RuntimeError, "source changed"):
                    proof.load_application_build(path)
            with self.assertRaisesRegex(RuntimeError, "owned application-build"):
                proof.load_application_build(root / "other.json")

    @unittest.skipUnless(os.name == "nt", "Windows batch argument handling")
    def test_flutter_path_with_spaces_is_invoked_without_shell_data(self):
        with tempfile.TemporaryDirectory(prefix="application tools ") as temporary:
            flutter = Path(temporary) / "flutter.bat"
            flutter.write_text("@echo off\n@echo fixture-tool-ok\n", encoding="ascii")
            command = builds.flutter_command(flutter, "--version")
            result = subprocess.run(command, capture_output=True, timeout=10)
            self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
            self.assertIn(b"fixture-tool-ok", result.stdout)
            for unsafe in ("x&whoami", "%PATH%", "x\ny", 'x"y'):
                with self.subTest(argument=unsafe), self.assertRaisesRegex(RuntimeError, "literal build options"):
                    builds.flutter_command(flutter, unsafe)
            with self.assertRaisesRegex(RuntimeError, "safe Flutter"):
                builds.flutter_command(Path(temporary) / "unsafe&name" / "flutter.bat", "--version")


class ApplicationPackageTests(unittest.TestCase):
    identity = "PlugAgenteHomologacao_0123456789ab"

    def state(self):
        return {"identity": self.identity, "revision": "a" * 40,
                "sourceTreeSha256": "b" * 64, "payloadTreeSha256": "c" * 64,
                "payloadFiles": {"data/app.so": "d" * 64, "plug_agente.exe": "e" * 64,
                                 **{name: "f" * 64 for name in binding.REBUILT_TOOLS}}}

    def test_input_is_reverified_and_reference_binds_exact_receipt_and_inventories(self):
        state = self.state()
        path = Path("application-build.json").absolute()
        with patch.object(binding, "load_application_build", return_value=state) as load, \
             patch.object(binding, "sha256", return_value="1" * 64):
            actual, reference = binding.application_input(path)
        self.assertEqual(actual, state)
        self.assertEqual(load.call_count, 2)
        self.assertEqual(reference["path"], str(path))
        self.assertEqual(reference["sha256"], "1" * 64)
        self.assertEqual(reference["sourceTreeSha256"], state["sourceTreeSha256"])

    def test_proof_replaced_during_verification_is_refused(self):
        with patch.object(binding, "load_application_build", return_value=self.state()), \
             patch.object(binding, "sha256", side_effect=["1" * 64, "2" * 64]):
            with self.assertRaisesRegex(RuntimeError, "changed during package"):
                binding.application_input(Path("application-build.json"))

    def test_only_named_fixture_updater_binaries_can_be_rebuilt(self):
        state = self.state()
        reference = {"path": "application-build.json", "sha256": "1" * 64}
        payload = {**state["payloadFiles"], **{name: "0" * 64 for name in binding.REBUILT_TOOLS}}
        with patch.object(binding, "application_input", return_value=(state, reference)):
            binding.verify_application_package(reference, self.identity, payload)
            for changed in ({**payload, "data/app.so": "0" * 64},
                            {**payload, "plug_agente.exe": "0" * 64},
                            {**payload, "extra.dll": "0" * 64},
                            {k: v for k, v in payload.items() if k != "data/app.so"}):
                with self.subTest(files=len(changed)), self.assertRaisesRegex(RuntimeError, "differs"):
                    binding.verify_application_package(reference, self.identity, changed)

    def test_other_identity_and_changed_reference_are_refused(self):
        state = self.state()
        reference = {"path": "application-build.json", "sha256": "1" * 64}
        with patch.object(binding, "application_input", return_value=(state, reference)):
            with self.assertRaisesRegex(RuntimeError, "identity changed"):
                binding.verify_application_package(reference, "PlugAgenteHomologacao_111111111111", state["payloadFiles"])
            with self.assertRaisesRegex(RuntimeError, "reference"):
                binding.verify_application_package({**reference, "sha256": "0" * 64}, self.identity, state["payloadFiles"])
        for invalid in (None, {}, {"path": 1}):
            with self.subTest(reference=invalid), self.assertRaisesRegex(RuntimeError, "explicit"):
                binding.verify_application_package(invalid, self.identity, state["payloadFiles"])

    @unittest.skipUnless(os.name == "nt", "Windows fixture packager preflight")
    def test_invalid_explicit_build_proof_never_creates_output_or_uses_stock_release(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary) / "build/homologation/windows-lifecycle-app-proof"
            with patch.object(fixtures, "require_fixture_root", return_value=root), \
                 patch.object(fixtures, "require_legacy_revision", return_value="a" * 40), \
                 patch.object(binding, "load_application_build", side_effect=RuntimeError("invalid proof")), \
                 patch.object(fixtures.shutil, "copytree", side_effect=AssertionError("Fallback must not run")):
                with self.assertRaisesRegex(RuntimeError, "invalid proof"):
                    fixtures.build_fixture(root, "a" * 40, Path(temporary) / "application-build.json")
            self.assertFalse(root.exists())


class BootstrapInputTests(unittest.TestCase):
    @unittest.skipUnless(os.name == "nt", "Windows compiled bootstrap")
    def test_invalid_proof_cannot_allocate_a_workspace(self):
        with patch.object(bootstrap, "application_input", side_effect=RuntimeError("invalid proof")), \
             patch.object(bootstrap.tempfile, "mkdtemp", side_effect=AssertionError("Must verify first")):
            with self.assertRaisesRegex(RuntimeError, "invalid proof"):
                bootstrap.prepare(Path("application-build.json"))

    @unittest.skipUnless(os.name == "nt", "Windows compiled bootstrap")
    def test_workspace_is_protected_and_output_contains_only_fixture_identity(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            state = {"root": str(root / "application"), "revision": "a" * 40,
                     "identity": "PlugAgenteHomologacao_0123456789ab"}
            with patch.object(bootstrap, "application_input", return_value=(state, {"sha256": "b" * 64})), \
                 patch.object(bootstrap.tempfile, "mkdtemp", return_value=str(root)), \
                 patch.object(bootstrap, "protect_backup") as protect:
                result = bootstrap.prepare(Path("application-build.json"))
            protect.assert_called_once_with(root)
            self.assertEqual(result["root"], str(root.resolve()))
            self.assertEqual(result["proofSha256"], "b" * 64)
            self.assertEqual(set(result), {"format", "root", "revision", "identity", "proofSha256", "executable"})
