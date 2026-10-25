"""Immutable Git input and explicit native derivations for bootstrap-only builds."""
from __future__ import annotations

import hashlib
import io
import os
from pathlib import Path, PurePosixPath
import re
import subprocess
import tarfile

from tool.updater.isolated_windows_fixture import PROJECT, require_identity, reject_reparse, rewrite_native

ENTRYPOINT = "tool/homologation/desktop_bootstrap_fixture.dart"
SAFE_ENV = b"APP_ENV=homologation\nENABLE_SQL_OPERATIONS=false\nAUTO_UPDATE_CHANNEL=internal\n"
SUPPORTED_BOOTSTRAP_SHA256 = "c4b88aa931bab28092890c97f164d22e9c10905e3858e94a29e6ca3ca2227fb7"
MAX_SOURCE_FILES = 10000
MAX_ARCHIVE_BYTES = 128 * 1024 * 1024


def relative_name(name: str) -> str:
    if (not isinstance(name, str) or not re.fullmatch(r"[^\\:\x00-\x1f]+", name)
            or PurePosixPath(name).is_absolute() or PurePosixPath(name).as_posix() != name
            or any(part in {".", "..", ".git"} for part in PurePosixPath(name).parts)):
        raise RuntimeError("Invalid application source path")
    return name


def source_root(identity: str, *, fresh: bool = False) -> Path:
    require_identity(identity)
    root = PROJECT / "build" / ("a" + identity[-12:])
    for path in (PROJECT / "build", root):
        if path.exists() or path.is_symlink():
            reject_reparse(path)
            if not path.is_dir():
                raise RuntimeError("Application source root is not a directory")
        elif not fresh:
            raise RuntimeError("Application source root is absent")
    if fresh and root.exists():
        raise RuntimeError("Refusing an existing application source root")
    return root


def tool_environment(raw: dict[str, str]) -> dict[str, str]:
    keys = {"PATH", "PATHEXT", "SYSTEMROOT", "SYSTEMDRIVE", "WINDIR", "COMSPEC", "OS", "TEMP", "TMP",
            "USERPROFILE", "HOME", "HOMEDRIVE", "HOMEPATH", "APPDATA", "LOCALAPPDATA",
            "PROGRAMDATA", "ALLUSERSPROFILE", "PROGRAMFILES", "PROGRAMFILES(X86)",
            "PROGRAMW6432", "COMMONPROGRAMFILES", "COMMONPROGRAMFILES(X86)",
            "COMMONPROGRAMW6432", "PROCESSOR_ARCHITECTURE", "NUMBER_OF_PROCESSORS",
            "FLUTTER_ROOT", "PUB_CACHE"}
    return {key: value for key, value in raw.items() if key.upper() in keys}


def git_output(*arguments: str) -> bytes:
    try:
        return subprocess.run(["git", *arguments], cwd=PROJECT,
                              env={**tool_environment(dict(os.environ)), "GIT_OPTIONAL_LOCKS": "0", "GIT_TERMINAL_PROMPT": "0"},
                              capture_output=True, check=True, timeout=60).stdout
    except (OSError, subprocess.SubprocessError) as error:
        raise RuntimeError("Application Git input could not be verified") from error


def git_files(revision: str) -> dict[str, str]:
    if not re.fullmatch(r"[a-f0-9]{40}", revision):
        raise RuntimeError("An explicit full application commit is required")
    if git_output("cat-file", "-t", revision).strip() != b"commit":
        raise RuntimeError("Application revision must identify a commit")
    git_output("merge-base", "--is-ancestor", revision, "HEAD")
    files = {}
    for entry in git_output("ls-tree", "-rz", revision).split(b"\0"):
        if not entry:
            continue
        metadata, raw_name = entry.split(b"\t", 1)
        mode, kind, blob = metadata.decode("ascii").split(" ")
        name = relative_name(raw_name.decode("utf-8"))
        if mode not in {"100644", "100755"} or kind != "blob":
            raise RuntimeError("Linked or nested Git inputs are refused")
        if PurePosixPath(name).name.startswith(".env") and PurePosixPath(name).name != ".env.example":
            raise RuntimeError("Environment files must not enter the application snapshot")
        if not re.fullmatch(r"[a-f0-9]{40}", blob) or name in files:
            raise RuntimeError("Invalid application Git inventory")
        files[name] = blob
    if not files or len(files) > MAX_SOURCE_FILES or ENTRYPOINT not in files:
        raise RuntimeError("Required bootstrap source is absent or exceeds its limit")
    if hashlib.sha256(git_output("show", f"{revision}:{ENTRYPOINT}")).hexdigest() != SUPPORTED_BOOTSTRAP_SHA256:
        raise RuntimeError("Bootstrap contract changed; review its isolation before building")
    contract = git_output("show", f"{revision}:windows/updater/contract.h")
    if b"constexpr bool kApplicationContractImplemented = false;" not in contract:
        raise RuntimeError("Application snapshot must preserve the disabled production gate")
    return files


def blob_hash(content: bytes) -> str:
    return hashlib.sha1(b"blob " + str(len(content)).encode("ascii") + b"\0" + content).hexdigest()


def export_archive(archive: bytes, root: Path, files: dict[str, str]) -> None:
    if len(archive) > MAX_ARCHIVE_BYTES:
        raise RuntimeError("Application archive exceeds its size limit")
    seen = set()
    with tarfile.open(fileobj=io.BytesIO(archive), mode="r:") as source:
        for entry in source:
            name = relative_name(entry.name.rstrip("/"))
            if entry.isdir():
                continue
            if not entry.isreg() or name not in files or name in seen or entry.size > MAX_ARCHIVE_BYTES:
                raise RuntimeError("Application archive contains an invalid entry")
            stream = source.extractfile(entry)
            if stream is None:
                raise RuntimeError("Application archive content is missing")
            content = stream.read(MAX_ARCHIVE_BYTES + 1)
            if len(content) != entry.size:
                raise RuntimeError("Application archive content is incomplete")
            if blob_hash(content) != files[name] and name.endswith(".ps1"):
                # Git archive applies eol=crlf. Reconstruct only the exact Git blob.
                content = content.replace(b"\r\n", b"\n")
            if blob_hash(content) != files[name]:
                raise RuntimeError("Application archive differs from the selected Git blob")
            target = root / name
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(content)
            seen.add(name)
    if seen != set(files):
        raise RuntimeError("Application archive does not cover the full Git inventory")


def requires_native_derivation(name: str) -> bool:
    return (name in {ENTRYPOINT, "windows/runner/main.cpp", "windows/runner/win32_window.cpp"}
            or (name.startswith(("windows/updater/", "windows/update_helper/", "windows/install_channel/"))
                and "/third_party/" not in name and PurePosixPath(name).suffix in {".cpp", ".h"}))


def derived_bytes(name: str, content: bytes, identity: str) -> bytes:
    require_identity(identity)
    if name == ENTRYPOINT:
        text = content.decode("utf-8-sig")
        if text.count("Future<void> main() async {\n") != 1:
            raise RuntimeError("Unsupported bootstrap installation check contract")
        text = "import 'package:flutter/services.dart';\nimport 'package:plug_agente/core/runtime/installation_bundle_check.dart';\n" + text
        text = text.replace("Future<void> main() async {\n", "Future<void> main(List<String> args) async {\n"
                            "  if (args.contains('--installation-check')) {\n"
                            "    WidgetsFlutterBinding.ensureInitialized();\n"
                            "    final result = await checkInstallationBundle(rootBundle);\n"
                            "    exit(result.fold((_) => 0, (_) => 3));\n"
                            "  }\n")
        return text.encode("utf-8")
    if name == "windows/runner/main.cpp":
        text = content.decode("utf-8-sig")
        requirements = {"PlugAgente_SingleInstance": 2, "FLUTTER_RUNNER_WIN32_WINDOW": 1,
                        'L"PlugAgenteUpdater"': 1, 'window.Create(L"plug_agente"': 1,
                        "if (!is_installation_check && !is_update_validation) RegisterCrashRestart();": 1,
                        "  PWSTR program_files = nullptr;": 1}
        if any(text.count(value) != count for value, count in requirements.items()):
            raise RuntimeError("Unsupported native runner; review its isolation before building")
        text = text.replace("PlugAgente_SingleInstance", identity + "_SingleInstance")
        text = text.replace("FLUTTER_RUNNER_WIN32_WINDOW", identity + "_WINDOW")
        text = text.replace('L"PlugAgenteUpdater"', 'L"' + identity + 'Updater"')
        text = text.replace('window.Create(L"plug_agente"', 'window.Create(L"' + identity + '"')
        text = text.replace("if (!is_installation_check && !is_update_validation) RegisterCrashRestart();",
                            "// The explicit fixture controller owns process lifetime.")
        guard_marker = "  wchar_t own_image[32768];" if "  wchar_t own_image[32768];" in text else "  PWSTR program_files = nullptr;"
        if text.count(guard_marker) != 1:
            raise RuntimeError("Unsupported native installation guard")
        text = text.replace(guard_marker,
                            '  if (!is_installation_check && GetEnvironmentVariableW(L"PLUG_AGENT_BOOTSTRAP_ROOT", nullptr, 0) == 0) return EXIT_FAILURE;\n\n'
                            + guard_marker)
        return text.encode("utf-8")
    if name == "windows/runner/win32_window.cpp":
        text = content.decode("utf-8-sig")
        if text.count("FLUTTER_RUNNER_WIN32_WINDOW") != 1:
            raise RuntimeError("Unsupported native window class")
        return text.replace("FLUTTER_RUNNER_WIN32_WINDOW", identity + "_WINDOW").encode("utf-8")
    if (name.startswith(("windows/updater/", "windows/update_helper/", "windows/install_channel/"))
            and "/third_party/" not in name and PurePosixPath(name).suffix in {".cpp", ".h"}):
        return rewrite_native(content.decode("utf-8-sig"), identity).encode("utf-8")
    return content


def source_bytes(root: Path, name: str) -> bytes:
    relative_name(name)
    path = root
    for part in PurePosixPath(name).parts:
        path /= part
        reject_reparse(path)
    if not path.is_file() or path.stat().st_nlink != 1:
        raise RuntimeError("Application source is not an independent regular file")
    return path.read_bytes()
