import json
import os
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from tool.updater import isolated_runtime as runtime


def image(machine=0x8664):
    content = bytearray(128)
    content[:2] = b"MZ"
    struct.pack_into("<I", content, 0x3c, 64)
    content[64:68] = b"PE\0\0"
    struct.pack_into("<H", content, 68, machine)
    return bytes(content)


class IsolatedRuntimeTests(unittest.TestCase):
    publisher = "CN=Microsoft Corporation, O=Microsoft Corporation, C=US"

    def test_wrong_architecture_and_non_pe_are_refused_before_signature_query(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "runtime.dll"
            for content in (b"not an image", image(0x14c), b"MZ" + b"x" * 90):
                path.write_bytes(content)
                with self.subTest(content=len(content)), patch.object(runtime, "signed_metadata", side_effect=AssertionError("Must not query invalid image")):
                    with self.assertRaisesRegex(RuntimeError, "AMD64"):
                        runtime.runtime_file(path)

    def test_signed_runtime_requires_version_floor_and_stable_bytes(self):
        with tempfile.TemporaryDirectory() as temporary:
            path = Path(temporary) / "runtime.dll"
            path.write_bytes(image())
            metadata = {"version": "14.50.35719.0", "publisher": self.publisher}
            with patch.object(runtime, "signed_metadata", return_value=metadata):
                result = runtime.runtime_file(path)
                self.assertEqual(result["version"], "14.50.35719.0")
            for version in ("14.42.34438.0", "malformed", "14.50"):
                with self.subTest(version=version), patch.object(runtime, "signed_metadata", return_value={**metadata, "version": version}):
                    with self.assertRaises(RuntimeError):
                        runtime.runtime_file(path)
            with patch.object(runtime, "signed_metadata", return_value=metadata), patch.object(runtime, "digest", side_effect=["a" * 64, "b" * 64]):
                with self.assertRaisesRegex(RuntimeError, "changed during"):
                    runtime.runtime_file(path)

    def test_untrusted_or_lookalike_publisher_is_refused(self):
        for status, publisher in (("NotSigned", self.publisher), ("Valid", "O=Other Publisher"),
                                  ("Valid", "O=Microsoft Corporation Impostor")):
            metadata = {"status": status, "publisher": publisher, "version": "14.50.35719.0"}
            process = subprocess.CompletedProcess([], 0, stdout=json.dumps(metadata).encode())
            with self.subTest(status=status, publisher=publisher), patch.object(runtime.subprocess, "run", return_value=process):
                with self.assertRaisesRegex(RuntimeError, "Microsoft runtime signature"):
                    runtime.signed_metadata(Path("runtime.dll"))
        metadata = {"status": "Valid", "publisher": self.publisher, "version": "14.50.35719.0"}
        with patch.object(runtime.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, stdout=json.dumps(metadata).encode())):
            self.assertEqual(runtime.signed_metadata(Path("runtime.dll")), metadata)

    def test_toolchain_declares_only_private_redist_and_rejects_cmake_injection(self):
        content = runtime.toolchain_content(Path("private-runtime"))
        self.assertEqual(content, 'set(MSVC_REDIST_DIR "private-runtime" CACHE PATH "Private fixture runtime")\n')
        for name in ('runtime"evil', "runtime;evil", "runtime${evil}", "runtime\nevil"):
            with self.subTest(name=name), self.assertRaisesRegex(RuntimeError, "CMake toolchain"):
                runtime.toolchain_content(Path(name))

    def test_runtime_reference_rejects_manifest_or_toolchain_changes(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            toolchain = root / "fixture-runtime.cmake"
            state = {"root": str(root / "runtime")}
            manifest = root / "runtime.json"
            reference = {"path": str(manifest), "sha256": "a" * 64, "toolchain": str(toolchain)}
            toolchain.write_text(runtime.toolchain_content(Path(state["root"])))
            with patch.object(runtime, "load_runtime", return_value=state), \
                 patch.object(runtime, "digest", return_value="a" * 64), \
                 patch.object(runtime, "require_fixture_artifact", return_value=toolchain):
                runtime.verify_runtime_reference(reference, root)
                toolchain.write_text('set(CMAKE_CXX_FLAGS "unrelated")')
                with self.assertRaisesRegex(RuntimeError, "toolchain changed"):
                    runtime.verify_runtime_reference(reference, root)
                with patch.object(runtime, "digest", return_value="b" * 64):
                    with self.assertRaisesRegex(RuntimeError, "manifest changed"):
                        runtime.verify_runtime_reference(reference, root)

    def test_arbitrary_manifest_name_and_reference_fields_are_refused(self):
        with self.assertRaisesRegex(RuntimeError, "owned runtime.json"):
            runtime.load_runtime(Path("other.json"))
        for value in (None, {}, {"path": "runtime.json"}):
            with self.subTest(value=value), self.assertRaisesRegex(RuntimeError, "Invalid private runtime"):
                runtime.verify_runtime_reference(value, Path("build"))

    def test_hard_linked_runtime_manifest_is_refused_before_json_or_signature_read(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            outside = root / "outside.txt"
            outside.write_text("must not be parsed as runtime metadata")
            owned = root / "fixture"
            owned.mkdir()
            manifest = owned / "runtime.json"
            os.link(outside, manifest)
            with patch.object(runtime, "require_fixture_root", return_value=owned), \
                 patch.object(runtime, "runtime_file", side_effect=AssertionError("Must not inspect runtime files")), \
                 patch.object(runtime.json, "loads", side_effect=AssertionError("Must not parse linked content")):
                with self.assertRaisesRegex(RuntimeError, "independent regular file"):
                    runtime.load_runtime(manifest)
