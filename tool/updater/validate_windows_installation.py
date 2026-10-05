"""Opt-in lifecycle validation on disposable Windows machines."""
from __future__ import annotations

import argparse
import configparser
import ctypes
import hashlib
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

OS_BUILDS = {"server2016": 14393, "server2019": 17763, "server2022": 20348, "server2025": 26100}


def matches_os(expected: str, build: int, server: bool) -> bool:
    if expected in OS_BUILDS:
        return server and build == OS_BUILDS[expected]
    if expected == "windows10":
        return not server and 10240 <= build < 22000
    if expected == "windows11":
        return not server and build >= 22000
    return False


def sha256(path: Path) -> str:
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest()


def read_installed_version(app: Path) -> tuple[int, ...]:
    metadata = configparser.ConfigParser()
    metadata.read(app / "install-mode.ini", encoding="utf-8-sig")
    version = metadata.get("installation", "workerVersion", fallback="")
    if not re.fullmatch(r"\d+\.\d+\.\d+\+\d+", version):
        raise RuntimeError("Lifecycle validation requires installers with installation-check and repair metadata")
    return tuple(map(int, re.split(r"[.+]", version)))


def run(command: list[str], log: Path, *, accepted=(0,)) -> int:
    result = subprocess.run(command, capture_output=True, timeout=240)
    log.write_bytes(result.stdout + result.stderr)
    if result.returncode not in accepted:
        raise RuntimeError(f"{Path(command[0]).name} failed with exit code {result.returncode}; see {log}")
    return result.returncode


def assert_clean_machine(expected: str) -> dict:
    import winreg

    if not ctypes.windll.shell32.IsUserAnAdmin():
        raise RuntimeError("Run validation as administrator on a disposable test machine")
    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"SOFTWARE\Microsoft\Windows NT\CurrentVersion") as key:
        build = int(winreg.QueryValueEx(key, "CurrentBuildNumber")[0])
        product = winreg.QueryValueEx(key, "ProductName")[0]
        installation_type = winreg.QueryValueEx(key, "InstallationType")[0]
    server = installation_type != "Client"
    if not matches_os(expected, build, server):
        raise RuntimeError(f"Expected {expected}, found {product} build {build}")
    if installation_type == "Server Core":
        raise RuntimeError("The Flutter desktop application requires Windows with Desktop Experience")
    for key_name in (r"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5E}_is1",
                     r"SYSTEM\CurrentControlSet\Services\PlugAgenteUpdater",
                     r"SOFTWARE\Classes\plugdb"):
        for hive in (winreg.HKEY_LOCAL_MACHINE, winreg.HKEY_CURRENT_USER):
            try:
                with winreg.OpenKey(hive, key_name):
                    raise RuntimeError(f"Existing Plug Agente state: {key_name}; use a clean VM")
            except FileNotFoundError:
                pass
    for path in (Path(os.environ["ProgramData"]) / "PlugAgente",
                 Path(os.environ["ProgramData"]) / "PlugAgenteUpdater",
                 Path(os.environ["ProgramFiles"]) / "PlugAgenteUpdater",
                 Path(os.environ["ProgramFiles"]) / "Plug Agente"):
        if path.exists():
            raise RuntimeError(f"Existing application data: {path}; use a clean VM")
    return {"product": product, "build": build, "installationType": installation_type}


def lock_core_against_replacement(executable: Path):
    kernel = ctypes.windll.kernel32
    kernel.CreateFileW.argtypes = [ctypes.c_wchar_p, ctypes.c_uint32, ctypes.c_uint32,
                                  ctypes.c_void_p, ctypes.c_uint32, ctypes.c_uint32, ctypes.c_void_p]
    kernel.CreateFileW.restype = ctypes.c_void_p
    handle = kernel.CreateFileW(str(executable), 0x80000000, 1 | 4, None, 3, 0, None)
    if handle == ctypes.c_void_p(-1).value:
        raise RuntimeError("Could not protect the core executable during optional repair")
    return handle


def validate(args) -> None:
    if os.name != "nt" or not args.allow_machine_changes:
        raise RuntimeError("Use --allow-machine-changes only on a disposable Windows VM")
    identity = assert_clean_machine(args.expected_os)
    evidence = args.evidence.resolve()
    evidence.mkdir(parents=True, exist_ok=True)
    result = {"os": identity, "status": "failed", "phases": [],
              "installerSha256": sha256(args.installer), "upgradeSha256": sha256(args.upgrade_installer)}
    root = Path(tempfile.mkdtemp(prefix="plug-installation-validation-"))
    result["testDirectory"] = str(root)
    try:
        app = root / "application"
        common = ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/NOCLOSEAPPLICATIONS",
                  f"/DIR={app}", "/AUTOUPDATE=0", '/MERGETASKS=!startup,!desktopicon,!autoupdate']
        retained_data = Path(os.environ["ProgramData"]) / "PlugAgente" / "installation-validation-data.txt"
        try:
            for phase, installer in (("installation", args.installer), ("upgrade", args.upgrade_installer)):
                run([str(installer.resolve()), *common, f"/LOG={evidence / (phase + '.log')}"],
                    evidence / (phase + "-output.log"))
                result["phases"].append(phase)
                version = read_installed_version(app)
                if phase == "installation":
                    initial_version = version
                    retained_data.write_text("user data retained across upgrade and uninstall", encoding="utf-8")
                elif version <= initial_version:
                    raise RuntimeError("The upgrade must install a newer version or build")
                elif retained_data.read_text(encoding="utf-8") != "user data retained across upgrade and uninstall":
                    raise RuntimeError("The upgrade did not preserve existing user data")
                result[phase + "Version"] = list(version)
                check = app / "plug_install_check.exe"
                run([str(check), "--core"], evidence / (phase + "-core.log"))
                run([str(check), "--odbc"], evidence / (phase + "-odbc.log"), accepted=(0, 2))
                if phase == "upgrade":
                    before = sha256(app / "plug_agente.exe")
                    handle = lock_core_against_replacement(app / "plug_agente.exe")
                    try:
                        run([str(installer.resolve()), *common, "/REPAIR=optional",
                             f"/LOG={evidence / 'repair.log'}"], evidence / "repair-output.log")
                    finally:
                        ctypes.windll.kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
                        ctypes.windll.kernel32.CloseHandle(handle)
                    if sha256(app / "plug_agente.exe") != before:
                        raise RuntimeError("Optional repair changed the application executable")
                    result["phases"].append("optional_repair")
            result["status"] = "passed"
        except Exception as error:
            result["error"] = str(error)
            raise
        finally:
            try:
                for report in app.glob("installation-warnings-*.log"):
                    (evidence / report.name).write_bytes(report.read_bytes())
                uninstaller = app / "unins000.exe"
                if uninstaller.exists():
                    run([str(uninstaller), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART",
                         f"/LOG={evidence / 'uninstall.log'}"], evidence / "uninstall-output.log")
                    if (app / "plug_agente.exe").exists():
                        raise RuntimeError("Uninstall left the application executable behind")
                    if retained_data.exists() and retained_data.read_text(encoding="utf-8") != "user data retained across upgrade and uninstall":
                        raise RuntimeError("Uninstall modified retained user data")
                    if "upgrade" in result["phases"] and not retained_data.exists():
                        raise RuntimeError("Uninstall removed retained user data")
                    result["phases"].append("uninstall")
                if result["status"] == "passed" and "uninstall" not in result["phases"]:
                    raise RuntimeError("Uninstall was not validated")
            except Exception as error:
                result["status"] = "failed"
                result["cleanupError"] = str(error)
                raise
            finally:
                (evidence / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    finally:
        if root.exists() and not any(root.iterdir()):
            root.rmdir()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--installer", type=Path, required=True)
    parser.add_argument("--upgrade-installer", type=Path, required=True)
    parser.add_argument("--expected-os", choices=[*OS_BUILDS, "windows10", "windows11"], required=True)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--allow-machine-changes", action="store_true")
    args = parser.parse_args()
    try:
        validate(args)
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        raise SystemExit(str(error)) from error


if __name__ == "__main__":
    main()
