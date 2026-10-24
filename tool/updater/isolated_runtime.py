"""Extract signed C++ runtime files into an owned fixture without installation."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import struct
import subprocess

from tool.updater.application_source import tool_environment
from tool.updater.isolated_windows_fixture import require_fixture_root, require_fixture_artifact, reject_reparse
from tool.updater.validate_existing_windows_installation import protect_backup

NAMES = ("concrt140.dll", "msvcp140.dll", "msvcp140_1.dll", "msvcp140_2.dll",
         "msvcp140_atomic_wait.dll", "msvcp140_codecvt_ids.dll", "vcruntime140.dll", "vcruntime140_1.dll")
MAX_BYTES = 32 * 1024 * 1024


def digest(path: Path) -> str:
    reject_reparse(path)
    if not path.is_file() or path.stat().st_nlink != 1 or path.stat().st_size > MAX_BYTES:
        raise RuntimeError("Runtime input must be a bounded independent regular file")
    return hashlib.sha256(path.read_bytes()).hexdigest()


def signed_metadata(path: Path) -> dict:
    environment = {**tool_environment(dict(os.environ)), "PLUG_FIXTURE_VERIFY_PATH": str(path)}
    script = "$ErrorActionPreference='Stop'; $p=$env:PLUG_FIXTURE_VERIFY_PATH; $s=Get-AuthenticodeSignature -LiteralPath $p; " \
             "$v=(Get-Item -LiteralPath $p).VersionInfo.FileVersionRaw.ToString(); " \
             "@{status=$s.Status.ToString(); publisher=$s.SignerCertificate.Subject; version=$v} | ConvertTo-Json -Compress"
    result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
                            env=environment, capture_output=True, check=True, timeout=30)
    metadata = json.loads(result.stdout.decode("utf-8-sig"))
    if metadata.get("status") != "Valid" or not re.search(r"(?:^|,\s*)O=Microsoft Corporation(?:,|$)", metadata.get("publisher", "")):
        raise RuntimeError("A valid Microsoft runtime signature is required")
    return metadata


def runtime_file(path: Path) -> dict:
    hashed = digest(path)
    content = path.read_bytes()
    if len(content) < 64 or content[:2] != b"MZ":
        raise RuntimeError("Runtime must be an AMD64 PE image")
    offset = struct.unpack_from("<I", content, 0x3c)[0]
    if offset > len(content) - 6 or content[offset:offset+4] != b"PE\0\0" or struct.unpack_from("<H", content, offset+4)[0] != 0x8664:
        raise RuntimeError("Runtime must be an AMD64 PE image")
    metadata = signed_metadata(path)
    try:
        version = tuple(int(part) for part in metadata["version"].split("."))
    except (KeyError, ValueError) as error:
        raise RuntimeError("Runtime version is not verifiable") from error
    if len(version) != 4 or version < (14, 43, 0, 0):
        raise RuntimeError("Runtime is older than the fixture minimum 14.43")
    if digest(path) != hashed:
        raise RuntimeError("Runtime changed during signature verification")
    return {"sha256": hashed, "version": metadata["version"], "publisher": metadata["publisher"]}


def load_runtime(path: Path) -> dict:
    if path.name != "runtime.json":
        raise RuntimeError("The owned runtime.json is required")
    root = require_fixture_root(path.parent)
    path = require_fixture_artifact(root, path)
    if path.stat().st_size > 65536:
        raise RuntimeError("Runtime manifest exceeds its size limit")
    digest(path)
    state = json.loads(path.read_text(encoding="utf-8"))
    if type(state.get("format")) is not int or state["format"] != 1 or state.get("scope") != "fixture-runtime-only" or state.get("root") != str(root):
        raise RuntimeError("Unsupported runtime manifest")
    actual = {name: runtime_file(require_fixture_artifact(root, root / "x64/Microsoft.VC143.CRT" / name)) for name in NAMES}
    if actual != state.get("files") or len({value["version"] for value in actual.values()}) != 1:
        raise RuntimeError("Runtime inventory or versions changed")
    return state


def prepare_runtime(output: Path, msi: Path, cab: Path) -> Path:
    if os.name != "nt":
        raise RuntimeError("Private runtime preparation requires Windows")
    output = require_fixture_root(output, fresh=True)
    package_hash, cabinet_hash = digest(msi), digest(cab)
    signed_metadata(msi)
    output.mkdir(parents=True)
    protect_backup(output)
    target = output / "x64/Microsoft.VC143.CRT"
    target.mkdir(parents=True)
    for name in NAMES:
        subprocess.run(["expand.exe", "-F:" + name + "_amd64", str(cab), str(target)],
                       env=tool_environment(dict(os.environ)), capture_output=True, check=True, timeout=30)
        (target / (name + "_amd64")).rename(target / name)
    files = {name: runtime_file(target / name) for name in NAMES}
    if digest(msi) != package_hash or digest(cab) != cabinet_hash:
        raise RuntimeError("Runtime extraction inputs changed")
    state = {"format": 1, "scope": "fixture-runtime-only", "root": str(output),
             "packageSha256": package_hash, "cabinetSha256": cabinet_hash, "files": files}
    path = output / "runtime.json"
    path.write_text(json.dumps(state, sort_keys=True, indent=2), encoding="utf-8")
    load_runtime(path)
    return path


def toolchain_content(runtime_root: Path) -> str:
    path = runtime_root.as_posix()
    if any(value in path for value in ('"', ';', '$', '\n', '\r')):
        raise RuntimeError("Runtime path cannot enter the CMake toolchain")
    return 'set(MSVC_REDIST_DIR "' + path + '" CACHE PATH "Private fixture runtime")\n'


def bind_runtime(path: Path, build_root: Path) -> dict:
    state = load_runtime(path)
    toolchain = build_root / "fixture-runtime.cmake"
    toolchain.write_text(toolchain_content(Path(state["root"])), encoding="utf-8")
    return {"path": str(path.absolute()), "sha256": digest(path), "toolchain": str(toolchain)}


def verify_runtime_reference(reference: dict, build_root: Path) -> None:
    if not isinstance(reference, dict) or set(reference) != {"path", "sha256", "toolchain"}:
        raise RuntimeError("Invalid private runtime reference")
    path = Path(reference["path"])
    state = load_runtime(path)
    if digest(path) != reference["sha256"]:
        raise RuntimeError("Private runtime manifest changed")
    expected = build_root / "fixture-runtime.cmake"
    toolchain = require_fixture_artifact(build_root, Path(reference["toolchain"]))
    digest(toolchain)
    if toolchain.stat().st_size > 4096:
        raise RuntimeError("Private runtime toolchain exceeds its size limit")
    if toolchain != expected or toolchain.read_text(encoding="utf-8") != toolchain_content(Path(state["root"])):
        raise RuntimeError("Private runtime toolchain changed")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--msi", type=Path, required=True)
    parser.add_argument("--cab", type=Path, required=True)
    args = parser.parse_args()
    print(prepare_runtime(args.output.absolute(), args.msi.absolute(), args.cab.absolute()))
