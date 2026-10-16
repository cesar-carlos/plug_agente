"""Explicit, namespaced installer/service acceptance on an existing Windows host."""
from __future__ import annotations

import argparse
import base64
from contextlib import closing
import ctypes
import json
import os
from pathlib import Path
import shutil
import sqlite3
import subprocess
import time

from tool.updater.isolated_windows_fixture import PROJECT, require_identity, assert_isolated_sources
from tool.updater.manifest import sign
from tool.updater.validate_existing_windows_installation import (
    configured_profile_digest, installation_paths, registry_snapshot, updater_snapshot, verify_no_updater_mutations,
)
from tool.updater.validate_windows_installation import sha256, lock_core_against_replacement


def load_fixture(path: Path) -> dict:
    path = path.resolve(strict=True)
    state = json.loads(path.read_text(encoding="utf-8"))
    identity = require_identity(state["identity"])
    root = Path(state["root"]).resolve(strict=True)
    if root != path.parent or root.parent != PROJECT / "build/homologation" or not root.name.startswith("windows-lifecycle-"):
        raise RuntimeError("Only an owned workspace lifecycle fixture is accepted")
    if state["appName"] != "Plug Agente Homologacao " + identity[-12:] or state["protocol"] != identity.lower().replace("_", "-"):
        raise RuntimeError("Fixture Windows identity mismatch")
    installer = Path(state["installer"]).resolve(strict=True)
    if installer.parent != root / "package" or sha256(installer) != state["installerSha256"]:
        raise RuntimeError("Fixture installer binding mismatch")
    if "legacyService" in state:
        legacy = Path(state["legacyService"]).resolve(strict=True)
        if legacy != root / "legacy/native/Release/plug_update_service.exe" or sha256(legacy) != state["legacyServiceSha256"]:
            raise RuntimeError("Historical supervisor binding mismatch")
    assert_isolated_sources(root, identity)
    state["app"] = str(Path(os.environ["ProgramFiles"]) / state["appName"])
    state["data"] = str(Path(os.environ["ProgramData"]) / identity)
    state["control"] = str(Path(os.environ["ProgramFiles"]) / (identity + "Updater"))
    state["updaterData"] = str(Path(os.environ["ProgramData"]) / (identity + "Updater"))
    return state


def host_snapshot() -> dict:
    app, data, vault = installation_paths()
    return {"profile": configured_profile_digest(data / "agent_config.db"), "vault": sha256(vault),
            "registry": registry_snapshot(), "updater": updater_snapshot(),
            "executables": {path.name: sha256(path) for path in app.glob("*.exe")}}


def run(command: list[str], *, log: Path | None = None, input_bytes: bytes | None = None, accepted=(0,)) -> bytes:
    result = subprocess.run(command, input=input_bytes, capture_output=True, timeout=240)
    if log:
        log.write_bytes(result.stdout + result.stderr)
    if result.returncode not in accepted:
        raise RuntimeError(f"{Path(command[0]).name} exited {result.returncode}; inspect the private phase log")
    return result.stdout


def ipc(client: Path, request: dict, *, expected_error: str | None = None) -> dict:
    response = json.loads(run([str(client), "--ipc"], input_bytes=json.dumps({"protocol": 1, **request}).encode(), accepted=(0, 1)))
    if expected_error:
        if response.get("ok") is not False or response.get("code") != expected_error:
            raise RuntimeError(f"IPC did not refuse with {expected_error}: {response.get('code')}")
    elif response.get("ok") is not True:
        raise RuntimeError("Fixture IPC failed: " + str(response.get("code")))
    return response


def signed_candidate(state: dict, **changes) -> dict:
    root = Path(state["root"])
    payload = {"formatVersion": 1, "version": "1.8.7+2", "channel": "stable",
               "installer": {"name": "PlugAgente-Setup-1.8.7.exe", "size": Path(state["installer"]).stat().st_size,
                             "sha256": state["installerSha256"]},
               "requirements": ["app.files"], "protocol": {"host": 1, "worker": 1},
               "data": {"schema": 1, "rollbackProtocol": 1}, "release": {"commit": "a" * 40, "tag": "v1.8.7"}, **changes}
    return sign(payload, base64.b64encode((root / "fixture-private-key").read_bytes()).decode())


def standard_user_phase(state: dict) -> None:
    if ctypes.windll.shell32.IsUserAnAdmin():
        raise RuntimeError("The caller phase must run without Windows elevation")
    root = Path(state["root"])
    client = Path(state["control"]) / "plug_update_client.exe"
    result = {"status": "failed", "elevated": False, "checks": []}
    try:
        capabilities = ipc(client, {"command": "capabilities"})["capabilities"]
        if capabilities["authorized"] is not True or capabilities["applicationReady"] is not False or capabilities["recoveryContract"] != 2:
            raise RuntimeError("Enrollment must not activate the unqualified application contract")
        result["checks"].append("real_scm_pipe_identity_and_activation_gate")
        probe = Path(state["control"]) / "standard-user-write-probe"
        try:
            probe.write_bytes(b"refuse")
        except PermissionError:
            result["checks"].append("control_directory_write_denied")
        else:
            probe.unlink()
            raise RuntimeError("A standard user can write updater control files")
        try:
            (Path(state["updaterData"]) / "policy.json").read_bytes()
        except PermissionError:
            result["checks"].append("protected_policy_read_denied")
        else:
            raise RuntimeError("A standard user can read the protected updater policy")
        copied = root / "unregistered-client.exe"
        shutil.copy2(client, copied)
        ipc(copied, {"command": "capabilities"}, expected_error="client_image_rejected")
        result["checks"].append("unregistered_client_image_refused")
        for command in ("--revoke", "--remove-service", "--prepare-host-upgrade"):
            response = json.loads(run([str(client), command], accepted=(1,)))
            if response.get("code") != "administrator_required":
                raise RuntimeError("Standard user administrative transition was not refused")
        result["checks"].append("administrative_transitions_denied")
        clear = b"private-fixture-vault-roundtrip"
        protected = json.loads(run([str(client), "--protect-secrets"], input_bytes=clear))["blob"]
        if run([str(client), "--unprotect-secrets"], input_bytes=protected.encode()) != clear:
            raise RuntimeError("Real DPAPI user roundtrip failed")
        (Path(state["data"]) / "fixture-vault.dpapi").write_text(protected, encoding="utf-8")
        result["checks"].append("real_user_dpapi_roundtrip")
        prepare = {"command": "prepare", "installerPath": state["installer"]}
        ipc(client, {**prepare, "manifest": signed_candidate(state, version="1.8.7+1")}, expected_error="version_replay_rejected")
        ipc(client, {**prepare, "manifest": signed_candidate(state, channel="beta")}, expected_error="channel_rejected")
        ipc(client, {**prepare, "manifest": signed_candidate(state, requirements=["fixture.unapproved"])}, expected_error="authorization_required")
        candidate = signed_candidate(state)
        tampered = {**candidate, "signatureBase64": base64.b64encode(bytes(64)).decode()}
        rejected = json.loads(run([str(client), "--ipc"], input_bytes=json.dumps({"protocol": 1, **prepare, "manifest": tampered}).encode(), accepted=(1,)))
        if rejected.get("ok") is not False:
            raise RuntimeError("Tampered manifest was accepted")
        result["checks"].append("replay_channel_capability_and_signature_refused")
        prepared = ipc(client, {**prepare, "manifest": candidate})["status"]
        operation = prepared["operationId"]
        if prepared["state"] != "preparing" or ipc(client, {**prepare, "manifest": candidate})["status"]["operationId"] != operation:
            raise RuntimeError("Preparation must be bound and idempotent")
        ipc(client, {"command": "start", "operationId": operation}, expected_error="transition_validation_required")
        cancelled = ipc(client, {"command": "cancel", "operationId": operation})["status"]
        if cancelled["state"] != "deferred" or cancelled.get("ownedByCaller") is not True:
            raise RuntimeError("Owned preparation did not cancel safely")
        ipc(client, {"command": "cancel", "operationId": operation})
        result["checks"].append("real_signed_staging_idempotence_blocked_apply_and_cancel")
        for _ in range(20):
            operation = ipc(client, {**prepare, "manifest": candidate})["status"]["operationId"]
            ipc(client, {"command": "cancel", "operationId": operation})
        result["checks"].append("twenty_signed_prepare_cancel_cycles")
        result["status"] = "passed"
    except Exception as error:
        result["error"] = str(error)
        raise
    finally:
        (root / "standard-result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")


def registry_value(hive, path: str, name: str = ""):
    import winreg
    try:
        with winreg.OpenKey(hive, path, 0, winreg.KEY_READ | winreg.KEY_WOW64_64KEY) as key:
            return winreg.QueryValueEx(key, name)[0]
    except FileNotFoundError:
        return None


def command_arguments(command: str | None) -> list[str]:
    if command is None:
        return []
    count = ctypes.c_int()
    parser = ctypes.windll.shell32.CommandLineToArgvW
    parser.argtypes = [ctypes.c_wchar_p, ctypes.POINTER(ctypes.c_int)]
    parser.restype = ctypes.POINTER(ctypes.c_wchar_p)
    arguments = parser(command, ctypes.byref(count))
    if not arguments:
        raise RuntimeError("Windows registry command cannot be parsed")
    try:
        return [arguments[index] for index in range(count.value)]
    finally:
        ctypes.windll.kernel32.LocalFree.argtypes = [ctypes.c_void_p]
        ctypes.windll.kernel32.LocalFree(arguments)


def verify_integrations(state: dict, installed: bool) -> None:
    import winreg
    app = Path(state["app"])
    protocol = registry_value(winreg.HKEY_LOCAL_MACHINE, "Software\\Classes\\" + state["protocol"] + r"\shell\open\command")
    startup = registry_value(winreg.HKEY_CURRENT_USER, r"Software\Microsoft\Windows\CurrentVersion\Run", state["appName"])
    if installed:
        if command_arguments(protocol) != [str(app / "plug_agente.exe"), "%1"] or command_arguments(startup) != [str(app / "plug_agente.exe"), "--autostart"]:
            raise RuntimeError("Installed Windows protocol/startup binding differs")
    elif protocol is not None or startup is not None:
        raise RuntimeError("Uninstall left protocol or startup registrations")


def administrator_phase(state: dict) -> None:
    import winreg
    if not ctypes.windll.shell32.IsUserAnAdmin():
        raise RuntimeError("Scoped installer acceptance requires Windows elevation")
    root, app, data = (Path(state[name]) for name in ("root", "app", "data"))
    control, updater_data = Path(state["control"]), Path(state["updaterData"])
    service = state["identity"] + "Updater"
    if any(path.exists() for path in (app, data, control, updater_data)) or (root / "lifecycle-result.json").exists():
        raise RuntimeError("Refusing an existing or already consumed fixture namespace")
    if registry_value(winreg.HKEY_LOCAL_MACHINE, rf"SYSTEM\CurrentControlSet\Services\{service}", "ImagePath") is not None:
        raise RuntimeError("Fixture service already exists")
    before = host_snapshot()
    result = {"status": "failed", "phases": [], "identity": state["identity"], "productionActivationGate": False}
    installer = state["installer"]
    common = ["/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/NOCLOSEAPPLICATIONS", f"/DIR={app}"]
    client = control / "plug_update_client.exe"

    def install(phase: str, *, repair=False, automatic=True) -> None:
        parameters = [*common, f"/AUTOUPDATE={int(automatic)}",
                      "/MERGETASKS=" + ("!startup,!desktopicon,!autoupdate" if repair and not automatic else "startup,!desktopicon,autoupdate")]
        if repair:
            parameters.append("/REPAIR=optional")
        run([installer, *parameters, f"/LOG={root / (phase + '.log')}"], log=root / (phase + "-output.log"))
        result["phases"].append(phase)
        (root / "lifecycle-progress.json").write_text(json.dumps(result, indent=2), encoding="utf-8")

    def uninstall(phase: str) -> None:
        run([str(app / "unins000.exe"), "/VERYSILENT", "/SUPPRESSMSGBOXES", "/NORESTART", f"/LOG={root / (phase + '.log')}"], log=root / (phase + "-output.log"))
        verify_integrations(state, False)
        if (app / "plug_agente.exe").exists() or registry_value(winreg.HKEY_LOCAL_MACHINE, rf"SYSTEM\CurrentControlSet\Services\{service}", "ImagePath") is not None:
            raise RuntimeError("Uninstall left the fixture app or service")
        result["phases"].append(phase)

    try:
        install("clean_install_enrollment")
        verify_integrations(state, True)
        run([str(app / "plug_install_check.exe"), "--core"], log=root / "installed-core.log")
        run([str(app / "plug_install_check.exe"), "--odbc"], log=root / "installed-odbc.log")
        with closing(sqlite3.connect(data / "fixture-retention.sqlite")) as connection, connection:
            connection.execute("CREATE TABLE retained_profile (id TEXT PRIMARY KEY)")
            connection.execute("INSERT INTO retained_profile VALUES ('private-retained-profile')")
        (data / "updates").mkdir(exist_ok=True)
        (data / "updates/download.tmp").write_bytes(b"disposable-download")
        (root / "standard-phase-ready").write_text("ready", encoding="utf-8")
        deadline = time.monotonic() + 300
        while not (root / "standard-result.json").exists():
            if time.monotonic() > deadline:
                raise RuntimeError("Standard-user controller did not complete")
            time.sleep(0.2)
        if json.loads((root / "standard-result.json").read_text())["status"] != "passed":
            raise RuntimeError("Standard-user service validation failed")
        result["phases"].append("standard_user_service_ipc_dpapi_and_denials")
        retained = {name: sha256(data / name) for name in ("fixture-retention.sqlite", "fixture-vault.dpapi")}
        policy_before = sha256(updater_data / "policy.json")
        worker_before = sha256(control / "workers/1.8.7+1/plug_update_worker.exe")
        core_before = sha256(app / "plug_agente.exe")
        handle = lock_core_against_replacement(app / "plug_agente.exe")
        try:
            install("optional_repair_without_updater", repair=True, automatic=False)
        finally:
            ctypes.windll.kernel32.CloseHandle.argtypes = [ctypes.c_void_p]
            ctypes.windll.kernel32.CloseHandle(handle)
        verify_no_updater_mutations(root / "optional_repair_without_updater.log")
        if policy_before != sha256(updater_data / "policy.json") or worker_before != sha256(control / "workers/1.8.7+1/plug_update_worker.exe") or core_before != sha256(app / "plug_agente.exe"):
            raise RuntimeError("Optional repair modified unrequested components")
        client.unlink()
        install("repair_missing_client", repair=True)
        run([str(client), "--check-host-contract"], log=root / "repaired-client-contract.log")
        run([str(client), "--prepare-host-upgrade"], log=root / "legacy-host-stop.log")
        historical_host = Path(state["legacyService"])
        shutil.copy2(historical_host, control / "plug_update_service.exe")
        policy = json.loads((updater_data / "policy.json").read_text())
        policy["recoveryContract"] = 1
        policy["enabled"] = True
        policy["binaryHashes"]["service"] = state["legacyServiceSha256"]
        (updater_data / "policy.json").write_text(json.dumps(policy), encoding="utf-8")
        run(["sc.exe", "start", service], log=root / "legacy-host-start.log")
        run([installer, *common, "/REPAIR=optional", "/AUTOUPDATE=1", f"/LOG={root / 'legacy-refused.log'}"], log=root / "legacy-refused-output.log", accepted=(7,))
        if "host_upgrade_required" not in (root / "legacy-refused.log").read_text(encoding="utf-8-sig"):
            raise RuntimeError("Legacy service contract was not explicitly refused")
        run([installer, *common, "/REPAIR=optional", "/AUTOUPDATE=1", "/UPGRADEUPDATERHOST=1", f"/LOG={root / 'explicit-host-upgrade.log'}"], log=root / "explicit-host-upgrade-output.log")
        run([str(client), "--check-host-contract"], log=root / "upgraded-host-contract.log")
        if sha256(control / "plug_update_service.exe") != sha256(root / "payload/updater/plug_update_service.exe"):
            raise RuntimeError("Explicit migration did not replace the historical supervisor")
        result["phases"].append("legacy_refused_then_explicit_host_upgrade")
        install("same_version_manual_reinstall")
        if any(sha256(data / name) != digest for name, digest in retained.items()):
            raise RuntimeError("Reinstall changed private retained SQLite/vault data")
        uninstall("uninstall")
        if (data / "updates").exists() or any(sha256(data / name) != digest for name, digest in retained.items()):
            raise RuntimeError("Uninstall did not preserve profile data and remove download cache")
        install("reinstall_with_residual_policy")
        verify_integrations(state, True)
        run([str(client), "--check-host-contract"], log=root / "residual-policy-contract.log")
        uninstall("final_uninstall")
        if any(sha256(data / name) != digest for name, digest in retained.items()):
            raise RuntimeError("Final uninstall modified retained private data")
        result["status"] = "passed"
    except Exception as error:
        result["error"] = str(error)
        raise
    finally:
        try:
            result["operationalInstallationPreserved"] = host_snapshot() == before
            if not result["operationalInstallationPreserved"]:
                result["status"] = "failed"
                raise RuntimeError("Operational installation changed during the scoped lifecycle")
        finally:
            (root / "lifecycle-result.json").write_text(json.dumps(result, indent=2), encoding="utf-8")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--fixture", type=Path, required=True)
    parser.add_argument("--phase", choices=["administrator", "standard-user"], required=True)
    parser.add_argument("--allow-machine-changes", action="store_true")
    args = parser.parse_args()
    if os.name != "nt" or not args.allow_machine_changes:
        raise SystemExit("Explicit Windows fixture authorization is required")
    state = load_fixture(args.fixture)
    (administrator_phase if args.phase == "administrator" else standard_user_phase)(state)
