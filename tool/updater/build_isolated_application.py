"""Build a source-qualified bootstrap-only desktop bundle without installing it."""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import uuid

from tool.updater.application_build_proof import MAX_PROOF_BYTES, canonical_hash, load_application_build, verify_sources
from tool.updater.application_source import ENTRYPOINT, SAFE_ENV, derived_bytes, export_archive, git_files, git_output, source_root, tool_environment
from tool.updater.isolated_windows_fixture import require_fixture_root, require_identity, reject_reparse
from tool.updater.lifecycle_payload import capture_payload, payload_tree_hash
from tool.updater.validate_existing_windows_installation import protect_backup


def run_logged(command: list[str] | str, cwd: Path, environment: dict[str, str], log: Path) -> None:
    with log.open("x", encoding="utf-8") as output:
        try:
            subprocess.run(command, cwd=cwd, env=environment, stdout=output, stderr=subprocess.STDOUT, check=True, timeout=1200)
        except (OSError, subprocess.SubprocessError) as error:
            raise RuntimeError(f"Application build step failed; inspect private {log.name}") from error


def flutter_command(flutter: Path, *args: str) -> str:
    if flutter.name.lower() != "flutter.bat" or re.search(r'[&|<>^%!"\r\n]', str(flutter)):
        raise RuntimeError("An explicit safe Flutter executable is required")
    if any(re.search(r'[&|<>^%!"\r\n]', argument) for argument in args):
        raise RuntimeError("Flutter arguments must contain only literal build options")
    prefix = subprocess.list2cmdline([os.environ.get("COMSPEC", "cmd.exe"), "/d", "/s", "/c"])
    invocation = subprocess.list2cmdline([str(flutter), *args])
    return prefix + ' "' + invocation + '"' 


def native_cache(source: Path, cache: Path) -> Path:
    lock = (source / "pubspec.lock").read_text(encoding="utf-8")
    block = re.search(r"^  odbc_fast:\n(.*?)(?=^  \w|^sdks:)", lock, re.M | re.S)
    version = re.search(r'^    version: "([0-9]+\.[0-9]+\.[0-9]+)"', block[1], re.M) if block else None
    if not version:
        raise RuntimeError("The snapshot must pin its published ODBC package")
    origin = cache / version[1] / "windows_x64"
    for path in (cache, origin.parent, origin, origin / "manifest.json", origin / "odbc_engine.dll"):
        reject_reparse(path)
    destination = source / "build/odbc-native/packages" / version[1] / "windows_x64"
    destination.mkdir(parents=True)
    for name in ("manifest.json", "odbc_engine.dll"):
        shutil.copy2(origin / name, destination / name)
    return destination / "odbc_engine.dll"


def build_application(output: Path, revision: str, flutter: Path, cache: Path, runtime_manifest: Path | None = None) -> Path:
    if os.name != "nt":
        raise RuntimeError("Isolated desktop builds require Windows")
    output = require_fixture_root(output, fresh=True)
    files = git_files(revision)
    flutter = flutter.resolve(strict=True)
    flutter_command(flutter, "--version")
    cache = cache.resolve(strict=True)
    identity = require_identity("PlugAgenteHomologacao_" + uuid.uuid4().hex[:12])
    source = source_root(identity, fresh=True)
    archive = git_output("archive", "--format=tar", revision)
    if runtime_manifest is not None:
        from tool.updater.isolated_runtime import load_runtime
        load_runtime(runtime_manifest)
    output.mkdir(parents=True)
    protect_backup(output)
    source.mkdir()
    protect_backup(source)
    export_archive(archive, source, files)
    captured = {}
    for name in files:
        path = source / name
        content = derived_bytes(name, path.read_bytes(), identity)
        path.write_bytes(content)
        captured[name] = hashlib.sha256(content).hexdigest()
    (source / ".env").write_bytes(SAFE_ENV)
    captured[".env"] = hashlib.sha256(SAFE_ENV).hexdigest()
    verify_sources(source, revision, identity, captured)
    environment = {**tool_environment(dict(os.environ)), "FLUTTER_SUPPRESS_ANALYTICS": "true",
                   "CI": "true", "AUTO_UPDATE_REQUIRE_VALID_SIGNATURE": "false",
                   "AUTO_UPDATE_FEED_PUBLIC_KEY": ""}
    runtime_reference = None
    if runtime_manifest is not None:
        from tool.updater.isolated_runtime import bind_runtime
        runtime_reference = bind_runtime(runtime_manifest, output)
        environment["CMAKE_TOOLCHAIN_FILE"] = runtime_reference["toolchain"]
    run_logged(flutter_command(flutter, "pub", "get", "--offline", "--enforce-lockfile"), source, environment, output / "pub-get.log")
    verify_sources(source, revision, identity, captured)
    binary = native_cache(source, cache)
    run_logged([sys.executable, "-m", "tool.odbc.prepare_package_native"], source, environment, output / "native-verify.log")
    environment["ODBC_FAST_NATIVE_LIBRARY"] = str(binary)
    run_logged(flutter_command(flutter, "build", "windows", "--release", "--no-pub", "--target", ENTRYPOINT), source, environment, output / "flutter-build.log")
    run_logged([sys.executable, "tool/elevated/build_elevated_runner.py", "--release-only"], source, environment, output / "elevated-helper.log")
    release = source / "build/windows/x64/runner/Release"
    run_logged([sys.executable, "-m", "tool.odbc.prepare_package_native", "--verify-bundle", str(release)], source, environment, output / "bundle-verify.log")
    verify_sources(source, revision, identity, captured)
    shutil.copytree(release, output / "payload", ignore=shutil.ignore_patterns("*.pdb", "*.ilk", "*.lib", "*.exp", "*.log"))
    payload = capture_payload(output)
    state = {"format": 1, "scope": "source-qualified-isolated-bootstrap", "root": str(output),
             "identity": identity, "revision": revision, "sourceRoot": str(source),
             "entrypoint": ENTRYPOINT, "productionActivationGate": False,
             "sourceFiles": captured, "sourceTreeSha256": canonical_hash(captured),
             "payloadFiles": payload, "payloadTreeSha256": payload_tree_hash(payload),
             "builtAt": datetime.now(timezone.utc).isoformat()}
    if runtime_reference is not None:
        state["runtimeInput"] = runtime_reference
    encoded = json.dumps(state, sort_keys=True, indent=2).encode("utf-8")
    if len(encoded) > MAX_PROOF_BYTES:
        raise RuntimeError("Application proof exceeds its size limit")
    receipt = output / "application-build.json"
    receipt.write_bytes(encoded)
    load_application_build(receipt)
    return receipt


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--revision", required=True)
    parser.add_argument("--flutter", type=Path, required=True)
    parser.add_argument("--native-cache", type=Path, required=True)
    parser.add_argument("--runtime-manifest", type=Path,
                        help="Explicit signed private runtime.json; never installs or replaces system files")
    args = parser.parse_args()
    print(build_application(args.output.absolute(), args.revision, args.flutter, args.native_cache, args.runtime_manifest))


if __name__ == "__main__":
    main()
