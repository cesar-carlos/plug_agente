"""Explicit repair validation on an existing Windows installation; never uninstalls."""
from __future__ import annotations

import argparse
import csv
from contextlib import closing
import ctypes
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import sqlite3
import subprocess
from datetime import datetime, timezone

from tool.updater.validate_windows_installation import lock_core_against_replacement, read_installed_version, sha256


def protect_backup(evidence: Path) -> None:
    identity = subprocess.run(["whoami", "/user", "/fo", "csv", "/nh"], capture_output=True, text=True, check=True)
    sid = next(csv.reader(identity.stdout.splitlines()))[1]
    if not sid.startswith("S-1-") or any(character not in "S-0123456789" for character in sid):
        raise RuntimeError("Cannot identify the snapshot owner")
    protected = subprocess.run(["icacls.exe", str(evidence), "/inheritance:r", "/grant:r",
                                f"*{sid}:(OI)(CI)(F)", "*S-1-5-18:(OI)(CI)(F)",
                                "*S-1-5-32-544:(OI)(CI)(F)", "/Q"], capture_output=True)
    if protected.returncode:
        raise RuntimeError("Cannot protect the local installation snapshot")
    # Children inherit the protected directory. Removing inheritance recursively
    # would leave existing files with an empty DACL and block the repair runner.
    for child in evidence.iterdir():
        inherited = subprocess.run(["icacls.exe", str(child), "/reset", "/T", "/Q"], capture_output=True)
        if inherited.returncode:
            raise RuntimeError("Cannot restore protected snapshot inheritance")


def configured_profile_digest(database: Path) -> dict:
    """Return only counts and hashes; do not emit configuration or credentials."""
    with closing(sqlite3.connect(database.as_uri() + "?mode=ro", uri=True, timeout=15)) as connection:
        tables = [row[0] for row in connection.execute("SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")]
        selected = [name for name in tables if any(term in name for term in ("config", "client_token", "hub_auth", "hub_session", "odbc_credential"))]
        if not selected:
            raise RuntimeError("No configured-profile tables found")
        result = {}
        for name in selected:
            identifier = '"' + name.replace('"', '""') + '"'
            rows = list(connection.execute(f"SELECT * FROM {identifier}"))
            canonical = sorted(json.dumps(row, default=lambda item: {"bytes": item.hex()}, separators=(",", ":")) for row in rows)
            result[name] = {"rows": len(rows), "sha256": hashlib.sha256("\n".join(canonical).encode()).hexdigest()}
        return result


def registry_snapshot() -> dict:
    import winreg

    result = {}
    for label, hive, path, name in (
        ("startup", winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", "Plug Agente"),
        ("approved", winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run", "Plug Agente"),
        ("protocol", winreg.HKEY_CLASSES_ROOT, r"plugdb\shell\open\command", ""),
        ("updater_authorized", winreg.HKEY_LOCAL_MACHINE, r"Software\Se7e Sistemas\PlugAgenteUpdater", "Authorized"),
    ):
        try:
            with winreg.OpenKey(hive, path, 0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY) as key:
                value, kind = winreg.QueryValueEx(key, name)
                result[label] = {"value": value.hex() if isinstance(value, bytes) else value, "kind": kind}
        except FileNotFoundError:
            result[label] = None
    return result


def installation_paths() -> tuple[Path, Path, Path]:
    import winreg

    with winreg.OpenKey(winreg.HKEY_LOCAL_MACHINE, r"Software\Microsoft\Windows\CurrentVersion\Uninstall\{A1B2C3D4-E5F6-4A5B-8C9D-0E1F2A3B4C5E}_is1", 0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY) as key:
        app = Path(winreg.QueryValueEx(key, "InstallLocation")[0]).resolve()
    expected = (Path(os.environ["ProgramFiles"]) / "Plug Agente").resolve()
    if app != expected or not (app / "plug_agente.exe").is_file():
        raise RuntimeError("Only the registered global Plug Agente installation is accepted")
    data = Path(os.environ["ProgramData"]) / "PlugAgente"
    vault = Path(os.environ["APPDATA"]) / "Se7e Sistemas" / "Plug Agente" / "flutter_secure_storage.dat"
    if not (data / "agent_config.db").is_file() or not vault.is_file():
        raise RuntimeError("Existing configured profile and encrypted vault are required")
    return app, data, vault


def updater_snapshot() -> dict:
    control = Path(os.environ["ProgramFiles"]) / "PlugAgenteUpdater"
    policy = Path(os.environ["ProgramData"]) / "PlugAgenteUpdater" / "policy.json"
    def fail_walk(error: OSError) -> None:
        raise error

    executables = {}
    for directory, _, files in os.walk(control, onerror=fail_walk):
        for name in files:
            if name.lower().endswith(".exe"):
                path = Path(directory) / name
                executables[str(path.relative_to(control))] = sha256(path)
    return {"executables": executables,
            "policySha256": sha256(policy) if policy.is_file() else None}


def verify_no_updater_mutations(log: Path) -> None:
    commands = re.findall(r"--(?:enroll|revoke|prepare-control|prepare-host-upgrade)\b",
                          log.read_text(encoding="utf-8-sig", errors="replace"))
    if commands:
        raise RuntimeError("Unrequested updater mutation in optional repair: " + ", ".join(sorted(set(commands))))


def prepare(installer: Path, evidence: Path) -> dict:
    app, data, vault = installation_paths()
    if evidence.exists():
        raise RuntimeError("Refusing to overwrite a previous host-validation snapshot")
    evidence.mkdir(parents=True)
    protect_backup(evidence)
    backup = evidence / "backup"
    backup.mkdir()
    shutil.copytree(app, backup / "application")
    for database in ("agent_config.db", "sql_operations.db"):
        source = data / database
        if source.is_file():
            with closing(sqlite3.connect(source.as_uri() + "?mode=ro", uri=True)) as live, closing(sqlite3.connect(backup / database)) as copied:
                live.backup(copied)
    shutil.copy2(data / "settings.json", backup / "settings.json")
    shutil.copy2(vault, backup / "flutter_secure_storage.dat")
    shutil.copy2(installer, backup / "installer.exe")
    state = {"format": 1, "createdAt": datetime.now(timezone.utc).isoformat(), "status": "prepared",
             "app": str(app), "data": str(data), "vault": str(vault), "evidence": str(evidence.resolve()),
             "installer": str((backup / "installer.exe").resolve()), "installerSha256": sha256(installer),
             "version": list(read_installed_version(app)), "profile": configured_profile_digest(data / "agent_config.db"),
             "vaultSha256": sha256(vault), "registry": registry_snapshot(), "updater": updater_snapshot(),
             "executables": {path.name: sha256(path) for path in app.glob("*.exe")}}
    (evidence / "state.json").write_text(json.dumps(state, indent=2), encoding="utf-8")
    return state


def validate_repair(evidence: Path) -> dict:
    result = {"status": "failed", "phases": []}
    try:
        if not ctypes.windll.shell32.IsUserAnAdmin():
            raise RuntimeError("Existing-installation repair requires Windows elevation")
        state = json.loads((evidence / "state.json").read_text(encoding="utf-8"))
        app, data, vault = installation_paths()
        installer = Path(state["installer"])
        if state["status"] != "prepared" or str(app) != state["app"] or sha256(installer) != state["installerSha256"]:
            raise RuntimeError("Prepared installation snapshot does not match")
        if configured_profile_digest(data / "agent_config.db") != state["profile"] or sha256(vault) != state["vaultSha256"]:
            raise RuntimeError("Profile changed since preparation; refresh snapshot before testing")
        if updater_snapshot() != state["updater"] or registry_snapshot() != state["registry"]:
            raise RuntimeError("Windows integration changed since preparation; refresh snapshot before testing")
        result["installerSha256"] = state["installerSha256"]
        handle = lock_core_against_replacement(app / "plug_agente.exe")
        try:
            command = [str(installer), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/NOCLOSEAPPLICATIONS",
                       "/REPAIR=optional", "/AUTOUPDATE=0", "/MERGETASKS=!startup,!desktopicon,!autoupdate",
                       f"/DIR={app}", f"/LOG={evidence / 'repair.log'}"]
            completed = subprocess.run(command, capture_output=True, timeout=240)
            (evidence / "repair-output.log").write_bytes(completed.stdout + completed.stderr)
            if completed.returncode != 0:
                raise RuntimeError(f"Optional repair failed: exit {completed.returncode}")
        finally:
            ctypes.windll.kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
            ctypes.windll.kernel32.CloseHandle(handle)
        result["phases"].append("real_installer_optional_repair")
        verify_no_updater_mutations(evidence / "repair.log")
        if updater_snapshot() != state["updater"]:
            raise RuntimeError("Optional repair modified updater binaries or policy")
        result["phases"].append("updater_binaries_policy_preserved_without_mutating_commands")
        if {path.name: sha256(path) for path in app.glob("*.exe")} != state["executables"]:
            raise RuntimeError("Optional repair modified installed executables")
        if configured_profile_digest(data / "agent_config.db") != state["profile"] or sha256(vault) != state["vaultSha256"]:
            raise RuntimeError("Optional repair modified the configured profile or encrypted vault")
        if registry_snapshot() != state["registry"]:
            raise RuntimeError("Optional repair modified startup, protocol or updater authorization")
        result["phases"].append("profile_vault_executables_integrations_preserved")
        for mode, arguments in (("core", ["--core"]), ("odbc", ["--odbc"]), ("data", ["--data", str(data)])):
            completed = subprocess.run([str(app / "plug_install_check.exe"), *arguments], capture_output=True, timeout=60)
            (evidence / f"{mode}.log").write_bytes(completed.stdout + completed.stderr)
            if completed.returncode != 0:
                raise RuntimeError(f"Installed {mode} probe failed: exit {completed.returncode}")
            result["phases"].append(mode)
        result["status"] = "passed"
        return result
    except Exception as error:
        result["error"] = str(error)
        raise
    finally:
        (evidence / "result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--prepare", action="store_true")
    parser.add_argument("--run-repair", action="store_true")
    parser.add_argument("--allow-machine-changes", action="store_true")
    parser.add_argument("--installer", type=Path)
    parser.add_argument("--evidence", type=Path, required=True)
    args = parser.parse_args()
    if os.name != "nt":
        raise SystemExit("Windows is required")
    if args.prepare and not args.run_repair and args.installer:
        state = prepare(args.installer.resolve(), args.evidence.resolve())
        print(json.dumps({"status": state["status"], "version": state["version"], "evidence": state["evidence"]}))
    elif args.run_repair and not args.prepare and args.allow_machine_changes:
        print(json.dumps(validate_repair(args.evidence.resolve())))
    else:
        raise SystemExit("Choose preparation, or explicitly authorized real-host repair")


if __name__ == "__main__":
    main()
