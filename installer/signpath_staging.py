from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from installer import build_installer as build
from tool.release.windows_version_info import PRODUCT_NAME, application_version, read_version_info

STAGE = build.INSTALLER_DIR / "signpath-work"
UNINSTALLER_ARTIFACT = "plug_agente_uninstaller.exe"


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def bundle_hashes() -> dict[str, str]:
    return {path.relative_to(build.BUILD_DIR).as_posix(): sha256(path)
            for path in sorted(build.BUILD_DIR.rglob("*")) if path.is_file()}


def configuration_hashes() -> dict[str, str]:
    paths = [*build.INSTALLER_DIR.glob("*.iss"), build.PROJECT_ROOT / "readme.md",
             build.PROJECT_ROOT / "LICENSE", * (build.INSTALLER_DIR / "wizard").glob("*.png"),
             build.PROJECT_ROOT / "windows/runner/resources/app_icon.ico"]
    return {path.relative_to(build.PROJECT_ROOT).as_posix(): sha256(path) for path in sorted(paths)}


def require_metadata(path: Path, version: str) -> None:
    info = read_version_info(path)
    if info["ProductName"].strip() != PRODUCT_NAME or info["ProductVersion"].strip() != version:
        raise ValueError(f"Unexpected product metadata: {path}")


def _certificate_directory(data: bytes) -> tuple[int, int, int, int]:
    if data[:2] != b"MZ":
        raise ValueError("Signing result is not a PE file")
    pe = struct.unpack_from("<I", data, 0x3C)[0]
    if data[pe:pe + 4] != b"PE\0\0":
        raise ValueError("Invalid PE header in signing result")
    optional = pe + 24
    magic = struct.unpack_from("<H", data, optional)[0]
    if magic not in (0x10B, 0x20B):
        raise ValueError("Unsupported signing result PE format")
    directory = optional + (112 if magic == 0x20B else 96) + 4 * 8
    offset, size = struct.unpack_from("<II", data, directory)
    return optional + 64, directory, offset, size


def require_unchanged_payload(original: Path, signed: Path) -> None:
    source = bytearray(original.read_bytes())
    result = bytearray(signed.read_bytes())
    checksum, directory, offset, size = _certificate_directory(result)
    source_checksum, source_directory, source_offset, source_size = _certificate_directory(source)
    if source_offset or source_size:
        raise ValueError("Signing input was already signed")
    if not size or offset < len(source) or offset + size != len(result) or offset - len(source) > 7:
        raise ValueError(f"Invalid appended Authenticode signature: {signed}")
    for data, check, entry in ((source, source_checksum, source_directory), (result, checksum, directory)):
        data[check:check + 4] = b"\0" * 4
        data[entry:entry + 8] = b"\0" * 8
    if result[:len(source)] != source or any(result[len(source):offset]):
        raise ValueError(f"Signing changed executable content: {signed}")


def signature_thumbprint(path: Path) -> str:
    escaped = str(path.resolve()).replace("'", "''")
    script = (f"$signature=Get-AuthenticodeSignature -LiteralPath '{escaped}'; "
              "if ($signature.Status -ne 'Valid') { throw 'Invalid Authenticode signature' }; "
              "$signature.SignerCertificate.Thumbprint")
    result = subprocess.run(["powershell.exe", "-NoProfile", "-NonInteractive", "-Command", script],
                            capture_output=True, text=True, check=True, timeout=60)
    thumbprint = result.stdout.strip()
    if len(thumbprint) != 40 or any(char not in "0123456789ABCDEF" for char in thumbprint):
        raise ValueError("Missing signing certificate identity")
    return thumbprint


def read_manifest() -> dict:
    manifest = json.loads((STAGE / "manifest.json").read_text(encoding="utf-8"))
    if manifest["version"] != application_version() or manifest["configuration"] != configuration_hashes():
        raise ValueError("Application version or installer configuration changed after staging")
    if manifest["channel"] != (build.resolve_auto_update_define("AUTO_UPDATE_CHANNEL") or "stable"):
        raise ValueError("Update channel changed after staging")
    for name, digest in manifest["inputs"].items():
        if sha256(STAGE / "unsigned-components" / name) != digest:
            raise ValueError(f"Signing input changed after staging: {name}")
    return manifest


def prepare() -> None:
    if STAGE.exists() and any(STAGE.iterdir()):
        raise ValueError(f"Signing staging directory must be empty: {STAGE}")
    unsigned = STAGE / "unsigned-components"
    unsigned.mkdir(parents=True, exist_ok=True)
    cache = STAGE / "uninstaller-cache"
    cache.mkdir()
    version = application_version()
    for name in build.PROJECT_EXECUTABLES:
        source = build.BUILD_DIR / name
        require_metadata(source, version)
        target = unsigned / name
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(source, target)
    result = subprocess.run(build.build_iscc_command(signed_uninstaller_dir=cache.resolve()),
                            cwd=build.INSTALLER_DIR, input="\n", capture_output=True, text=True, timeout=300)
    uninstallers = list(cache.glob("*.e32"))
    if result.returncode != 2 or len(uninstallers) != 1 or "please attach your digital signature" not in result.stderr:
        raise ValueError("Could not stage the unsigned Inno uninstaller:\n" + result.stdout + result.stderr)
    require_metadata(uninstallers[0], version)
    shutil.copy2(uninstallers[0], unsigned / UNINSTALLER_ARTIFACT)
    inputs = {name: sha256(unsigned / name) for name in (*build.PROJECT_EXECUTABLES, UNINSTALLER_ARTIFACT)}
    manifest = {"version": version, "channel": build.resolve_auto_update_define("AUTO_UPDATE_CHANNEL") or "stable",
                "configuration": configuration_hashes(), "bundle": bundle_hashes(),
                "uninstaller": uninstallers[0].name, "inputs": inputs}
    (STAGE / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"SignPath unsigned inputs ready: {unsigned}")


def package(signed_directory: Path) -> None:
    manifest = read_manifest()
    if bundle_hashes() != manifest["bundle"]:
        raise ValueError("Application bundle changed after staging")
    actual = {path.relative_to(signed_directory).as_posix() for path in signed_directory.rglob("*") if path.is_file()}
    if actual != set(manifest["inputs"]):
        raise ValueError("Returned signing artifact contains missing or unexpected files")
    thumbprints = set()
    for name in manifest["inputs"]:
        signed = signed_directory / name
        require_unchanged_payload(STAGE / "unsigned-components" / name, signed)
        require_metadata(signed, manifest["version"])
        build.verify_signed_file(signed)
        thumbprints.add(signature_thumbprint(signed))
    if len(thumbprints) != 1:
        raise ValueError("All project components must use the same signing certificate")
    for name in build.PROJECT_EXECUTABLES:
        shutil.copy2(signed_directory / name, build.BUILD_DIR / name)
    cache = STAGE / "uninstaller-cache"
    shutil.copy2(signed_directory / UNINSTALLER_ARTIFACT, cache / manifest["uninstaller"])
    build.run(build.build_iscc_command(signed_uninstaller_dir=cache.resolve()), cwd=build.INSTALLER_DIR)
    installer = build.find_generated_installer()
    unsigned_installer = STAGE / "unsigned-installer" / installer.name
    unsigned_installer.parent.mkdir()
    shutil.copy2(installer, unsigned_installer)
    manifest["certificate"] = next(iter(thumbprints))
    manifest["installer_sha256"] = sha256(unsigned_installer)
    manifest["signed_bundle"] = bundle_hashes()
    (STAGE / "manifest.json").write_text(json.dumps(manifest, indent=2), encoding="utf-8")
    print(f"SignPath installer signing input ready: {unsigned_installer}")


def finalize(signed_installer: Path) -> None:
    manifest = read_manifest()
    if bundle_hashes() != manifest["signed_bundle"]:
        raise ValueError("Signed application bundle changed before final verification")
    original = STAGE / "unsigned-installer" / build.find_generated_installer().name
    if sha256(original) != manifest["installer_sha256"]:
        raise ValueError("Installer signing input changed")
    require_unchanged_payload(original, signed_installer)
    require_metadata(signed_installer, manifest["version"])
    build.verify_signed_file(signed_installer)
    if signature_thumbprint(signed_installer) != manifest["certificate"]:
        raise ValueError("Installer and components must use the same signing certificate")
    shutil.copy2(signed_installer, build.find_generated_installer())
    print("All SignPath component, uninstaller and installer signatures verified")


def main() -> None:
    parser = argparse.ArgumentParser()
    group = parser.add_mutually_exclusive_group(required=True)
    group.add_argument("--package", type=Path, metavar="SIGNED_COMPONENTS")
    group.add_argument("--finalize", type=Path, metavar="SIGNED_INSTALLER")
    group.add_argument("--parameters", action="store_true")
    args = parser.parse_args()
    try:
        if args.parameters:
            manifest = read_manifest()
            info = read_version_info(STAGE / "unsigned-components" / UNINSTALLER_ARTIFACT)
            print("version_json=" + json.dumps(manifest["version"]))
            print("inno_product_name_json=" + json.dumps(info["ProductName"]))
            print("inno_product_version_json=" + json.dumps(info["ProductVersion"]))
        elif args.package:
            package(args.package)
        else:
            finalize(args.finalize)
    except (OSError, ValueError, KeyError, subprocess.SubprocessError) as error:
        raise SystemExit(f"SignPath staging failed: {error}") from error


if __name__ == "__main__":
    main()
