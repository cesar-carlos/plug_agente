"""Build a private Windows installer/service fixture from production sources.

Only product identities and payload locations are rewritten. Updater activation,
signature verification, ACLs and process/pipe checks keep their production code.
These derived packages are never release artifacts.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import uuid

from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey
from cryptography.hazmat.primitives.serialization import Encoding, PrivateFormat, NoEncryption, PublicFormat

from installer.build_installer import find_iscc
from tool.updater.validate_existing_windows_installation import protect_backup
from tool.updater.validate_windows_installation import sha256

PROJECT = Path(__file__).resolve().parents[2]
IDENTITY = re.compile(r"PlugAgenteHomologacao_[a-f0-9]{12}")


def require_identity(name: str) -> str:
    if not IDENTITY.fullmatch(name):
        raise ValueError("An exclusive PlugAgenteHomologacao_<12 hex> identity is required")
    return name


def reject_reparse(path: Path) -> None:
    metadata = path.lstat()
    if stat.S_ISLNK(metadata.st_mode) or getattr(metadata, "st_file_attributes", 0) & getattr(stat, "FILE_ATTRIBUTE_REPARSE_POINT", 0x400):
        raise RuntimeError("Linked lifecycle fixture paths are not accepted")


def require_fixture_root(path: Path, *, fresh: bool = False) -> Path:
    owned = Path(os.path.abspath(path))
    parent = PROJECT / "build/homologation"
    if owned.parent != parent or not re.fullmatch(r"windows-lifecycle-[a-z0-9-]{1,80}", owned.name):
        raise RuntimeError("Only an owned workspace lifecycle fixture is accepted")
    for candidate in (PROJECT / "build", parent, owned):
        try:
            reject_reparse(candidate)
        except FileNotFoundError:
            if fresh:
                continue
            raise
        if not candidate.is_dir():
            raise RuntimeError("Lifecycle fixture directory is invalid")
    if fresh and owned.exists():
        raise RuntimeError("Refusing an existing lifecycle fixture")
    return owned


def require_fixture_artifact(root: Path, path: Path) -> Path:
    artifact = Path(os.path.abspath(path))
    try:
        relative = artifact.relative_to(root)
    except ValueError as error:
        raise RuntimeError("Lifecycle artifact is outside its owned fixture") from error
    current = root
    reject_reparse(current)
    for part in relative.parts:
        current = current / part
        reject_reparse(current)
    if not artifact.is_file():
        raise RuntimeError("Lifecycle fixture artifact is not a regular file")
    return artifact


def rewrite_native(source: str, identity: str) -> str:
    require_identity(identity)
    return (source.replace("PlugAgenteUpdater", identity + "Updater")
            .replace('L"PlugAgente"', f'L"{identity}"')
            .replace("Plug Agente Updater", "Plug Agente Homologacao " + identity[-12:] + " Updater")
            .replace("PlugAgenteSetup", identity + "Setup"))


def rewrite_installer(source: str, identity: str, app_id: str, payload: Path) -> str:
    require_identity(identity)
    uuid.UUID(app_id)
    source = (source.replace("{commonappdata}\\PlugAgente", "{commonappdata}\\" + identity)
              .replace("PlugAgenteUpdater", identity + "Updater")
              .replace('"Plug Agente"', f'"Plug Agente Homologacao {identity[-12:]}"')
              .replace("{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5E}", "{" + app_id + "}")
              .replace("Classes\\plugdb", "Classes\\" + identity.lower().replace("_", "-"))
              .replace("PlugAgenteSetup", identity + "Setup"))
    paths = {r"..\build\windows\x64\runner\Release": str(payload),
             r"..\LICENSE": str(PROJECT / "LICENSE"),
             r"..\assets\fonts\montserrat\OFL.txt": str(PROJECT / "assets/fonts/montserrat/OFL.txt"),
             r"..\windows\runner\resources\app_icon.ico": str(PROJECT / "windows/runner/resources/app_icon.ico"),
             r"wizard\wizard-image.png": str(PROJECT / "installer/wizard/wizard-image.png"),
             r"wizard\wizard-small-image.png": str(PROJECT / "installer/wizard/wizard-small-image.png")}
    for original, replacement in paths.items():
        source = source.replace(original, replacement)
    return source


def assert_isolated_sources(root: Path, identity: str) -> None:
    require_identity(identity)
    forbidden = ("PlugAgenteUpdater", 'L"PlugAgente"', "Classes\\plugdb", "Global\\PlugAgenteSetup",
                 "{commonappdata}\\PlugAgente\\", "{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5E}")
    for directory, extensions in ((root / "installer", {".iss"}), (root / "windows/updater", {".cpp", ".h"})):
        for path in directory.rglob("*"):
            if path.suffix not in extensions or "third_party" in path.parts:
                continue
            source = path.read_text(encoding="utf-8-sig")
            if any(value in source for value in forbidden):
                raise RuntimeError(f"Operational identity remains in fixture source: {path.name}")
    contract = (root / "windows/updater/contract.h").read_text(encoding="utf-8")
    if "constexpr bool kApplicationContractImplemented = false;" not in contract:
        raise RuntimeError("Fixture must preserve the production activation gate")


def cmake_path() -> str:
    command = shutil.which("cmake")
    if command:
        return command
    candidate = Path(r"C:\Program Files\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe")
    if not candidate.is_file():
        raise RuntimeError("CMake from Visual Studio 2022 is required")
    return str(candidate)


def require_legacy_revision(revision: str) -> str:
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise RuntimeError("An explicit full historical commit is required")
    try:
        subprocess.run(["git", "merge-base", "--is-ancestor", revision, "HEAD"], cwd=PROJECT,
                       capture_output=True, check=True)
        contract = subprocess.run(["git", "show", f"{revision}:windows/updater/contract.h"], cwd=PROJECT,
                                  capture_output=True, text=True, check=True).stdout
    except subprocess.CalledProcessError as error:
        raise RuntimeError("Historical supervisor must exist in the local ancestry") from error
    if "kRecoveryContractVersion = 1;" not in contract or "kApplicationContractImplemented = false;" not in contract:
        raise RuntimeError("The explicit historical source must be the disabled recovery-v1 supervisor")
    return revision


def build_legacy_supervisor(output: Path, identity: str, public_key: str, revision: str) -> dict:
    """Preserve an actual previous supervisor, rather than only editing policy."""
    require_identity(identity)
    output = require_fixture_root(output)
    revision = require_legacy_revision(revision)
    legacy = output / "legacy"
    if legacy.exists():
        raise RuntimeError("Refusing to replace a historical supervisor fixture")
    for name in ("updater", "update_helper"):
        destination = legacy / "windows" / name
        shutil.copytree(PROJECT / "windows" / name, destination)
        tracked = subprocess.run(["git", "ls-tree", "-r", "--name-only", revision, f"windows/{name}"],
                                 cwd=PROJECT, capture_output=True, text=True, check=True).stdout.splitlines()
        for relative in tracked:
            path = Path(relative)
            if path.suffix not in {".cpp", ".h"} and path.name != "CMakeLists.txt":
                continue
            if "third_party" in path.parts:
                continue
            original = subprocess.run(["git", "show", f"{revision}:{relative}"], cwd=PROJECT,
                                      capture_output=True, check=True).stdout.decode("utf-8-sig")
            (legacy / path).write_text(rewrite_native(original, identity), encoding="utf-8")
    contract = (legacy / "windows/updater/contract.h").read_text(encoding="utf-8")
    if "kRecoveryContractVersion = 1;" not in contract or "kApplicationContractImplemented = false;" not in contract:
        raise RuntimeError("The explicit historical source must be the disabled recovery-v1 supervisor")
    environment = {**os.environ, "AUTO_UPDATE_FEED_PUBLIC_KEY": public_key, "AUTO_UPDATE_REQUIRE_VALID_SIGNATURE": "false"}
    commands = [[cmake_path(), "-S", str(legacy / "windows/updater"), "-B", str(legacy / "native"), "-A", "x64"],
                [cmake_path(), "--build", str(legacy / "native"), "--config", "Release", "--target", "plug_update_service", "--parallel", "4"]]
    for index, command in enumerate(commands):
        with (output / f"legacy-native-{index}.log").open("w", encoding="utf-8") as log:
            subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=240)
    binary = legacy / "native/Release/plug_update_service.exe"
    return {"legacyService": str(binary), "legacyServiceSha256": sha256(binary), "legacySourceCommit": revision}


def build_fixture(output: Path, legacy_revision: str) -> Path:
    if os.name != "nt":
        raise RuntimeError("Windows and a new private output directory are required")
    output = require_fixture_root(output, fresh=True)
    legacy_revision = require_legacy_revision(legacy_revision)
    output.mkdir(parents=True)
    protect_backup(output)
    identity = require_identity("PlugAgenteHomologacao_" + uuid.uuid4().hex[:12])
    app_id = str(uuid.uuid4()).upper()
    payload = output / "payload"
    shutil.copytree(PROJECT / "build/windows/x64/runner/Release", payload,
                    ignore=shutil.ignore_patterns("*.pdb", "*.ilk", "*.lib", "*.exp", "*.log", "updater"))
    if not (payload / "data/app.so").is_file():
        raise RuntimeError("An existing complete Release bundle is required")
    sources = {}
    for name in ("updater", "update_helper"):
        source = PROJECT / "windows" / name
        destination = output / "windows" / name
        shutil.copytree(source, destination)
        for path in destination.rglob("*"):
            if path.suffix in {".cpp", ".h"} and "third_party" not in path.parts:
                original = path.read_text(encoding="utf-8-sig")
                sources[str(path.relative_to(output))] = hashlib.sha256(original.encode()).hexdigest()
                path.write_text(rewrite_native(original, identity), encoding="utf-8")
    (output / "test/fixtures").mkdir(parents=True)
    shutil.copy2(PROJECT / "test/fixtures/updater_manifest_v1.json", output / "test/fixtures/updater_manifest_v1.json")
    (output / "installer").mkdir()
    for path in (PROJECT / "installer").glob("*.iss"):
        original = path.read_text(encoding="utf-8-sig")
        sources["installer/" + path.name] = hashlib.sha256(original.encode()).hexdigest()
        (output / "installer" / path.name).write_text(rewrite_installer(original, identity, app_id, payload), encoding="utf-8")
    assert_isolated_sources(output, identity)
    private = Ed25519PrivateKey.generate()
    private_bytes = private.private_bytes(Encoding.Raw, PrivateFormat.Raw, NoEncryption())
    (output / "fixture-private-key").write_bytes(private_bytes)
    public = base64.b64encode(private.public_key().public_bytes(Encoding.Raw, PublicFormat.Raw)).decode()
    environment = {**os.environ, "AUTO_UPDATE_FEED_PUBLIC_KEY": public, "AUTO_UPDATE_REQUIRE_VALID_SIGNATURE": "false"}
    cmake = cmake_path()
    commands = [[cmake, "-S", str(output / "windows/updater"), "-B", str(output / "native"), "-A", "x64"],
                [cmake, "--build", str(output / "native"), "--config", "Release", "--parallel", "4"]]
    for index, command in enumerate(commands):
        with (output / f"native-{index}.log").open("w", encoding="utf-8") as log:
            subprocess.run(command, env=environment, stdout=log, stderr=subprocess.STDOUT, check=True, timeout=240)
    updater = payload / "updater"
    updater.mkdir()
    for name in ("service", "client", "worker"):
        shutil.copy2(output / f"native/Release/plug_update_{name}.exe", updater)
    installer = output / "package/PlugAgente-Setup-1.8.7.exe"
    installer.parent.mkdir()
    with (output / "installer-build.log").open("w", encoding="utf-8") as log:
        subprocess.run([find_iscc(), "/Q", f"/O{installer.parent}", "/DMyAppWorkerVersion=1.8.7+1",
                        str(output / "installer/setup.iss")], stdout=log, stderr=subprocess.STDOUT, check=True, timeout=240)
    state = {"format": 1, "identity": identity, "appId": app_id, "protocol": identity.lower().replace("_", "-"),
             "appName": "Plug Agente Homologacao " + identity[-12:], "root": str(output.resolve()),
             "installer": str(installer), "installerSha256": sha256(installer), "publicKey": public,
             "originalSourceHashes": sources, "payloadVersion": "1.8.7+1", "productionActivationGate": False}
    state.update(build_legacy_supervisor(output, identity, public, legacy_revision))
    manifest = output / "fixture.json"
    manifest.write_text(json.dumps(state, indent=2), encoding="utf-8")
    return manifest


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--legacy-revision", required=True,
                        help="Exact ancestor commit containing the disabled recovery-v1 supervisor")
    args = parser.parse_args()
    print(build_fixture(args.output.absolute(), args.legacy_revision))
