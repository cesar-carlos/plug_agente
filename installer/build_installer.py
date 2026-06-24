#!/usr/bin/env python3
"""
Orquestra o build do instalador Windows: build Flutter e compila Inno Setup.

Fluxo: flutter build windows --release -> ISCC setup.iss
Opcional: --sync-version executa update_version.py antes do build.

Saida: installer/dist/PlugAgente-Setup-{versao}.exe

Requisitos: Flutter no PATH, Inno Setup 6 (ISCC no PATH ou em Program Files).
Execute a partir da raiz: python installer/build_installer.py
"""

import argparse
import os
import shutil
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Sequence

PROJECT_ROOT = Path(__file__).resolve().parent.parent
INSTALLER_DIR = PROJECT_ROOT / "installer"
BUILD_DIR = PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Release"
SETUP_ISS = INSTALLER_DIR / "setup.iss"
DIST_DIR = INSTALLER_DIR / "dist"
ENV_FILE = PROJECT_ROOT / ".env"
DEFAULT_TIMESTAMP_URL = "http://timestamp.digicert.com"

ISCC_PATHS = [
    "ISCC",
    r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    r"C:\Program Files\Inno Setup 6\ISCC.exe",
]

SIGNTOOL_PATHS = [
    "signtool",
    r"C:\Program Files (x86)\Windows Kits\10\bin",
    r"C:\Program Files\Windows Kits\10\bin",
]


def find_iscc() -> str:
    for path in ISCC_PATHS:
        if path == "ISCC":
            if shutil.which("ISCC"):
                return "ISCC"
        elif Path(path).exists():
            return path
    raise SystemExit(
        "Inno Setup (ISCC) nao encontrado. Instale em "
        "https://jrsoftware.org/isinfo.php",
    )


def find_signtool() -> Optional[str]:
    if shutil.which("signtool"):
        return "signtool"

    for root in SIGNTOOL_PATHS[1:]:
        root_path = Path(root)
        if not root_path.exists():
            continue
        candidates = sorted(
            root_path.glob(r"*\x64\signtool.exe"),
            key=lambda path: path.as_posix(),
            reverse=True,
        )
        if candidates:
            return str(candidates[0])
    return None


def resolve_command(cmd: Sequence[str]) -> List[str]:
    args = list(cmd)
    if not args:
        raise SystemExit("Comando vazio")

    executable = args[0]
    if Path(executable).parent == Path("."):
        executable = shutil.which(executable) or executable

    if Path(executable).suffix.lower() in {".bat", ".cmd"}:
        return ["cmd.exe", "/d", "/c", executable, *args[1:]]

    return [executable, *args[1:]]


def run(cmd: Sequence[str], cwd: Optional[Path] = None) -> None:
    resolved_cmd = resolve_command(cmd)
    try:
        subprocess.run(
            resolved_cmd,
            cwd=cwd or PROJECT_ROOT,
            check=True,
        )
    except FileNotFoundError as error:
        executable = resolved_cmd[0] if resolved_cmd else "command"
        raise SystemExit(f"Comando nao encontrado: {executable}") from error
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from error


def read_env_flag(key: str, *, default: bool = False) -> bool:
    value = os.environ.get(key) or read_env_value(key)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "on"}


def resolve_auto_update_feed_url() -> Optional[str]:
    return os.environ.get("AUTO_UPDATE_FEED_URL") or read_env_value("AUTO_UPDATE_FEED_URL")


def resolve_auto_update_define(key: str) -> Optional[str]:
    return os.environ.get(key) or read_env_value(key)


def read_env_value(key: str) -> Optional[str]:
    if not ENV_FILE.exists():
        return None

    for raw_line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        env_key, value = line.split("=", 1)
        if env_key.strip() != key:
            continue
        normalized = value.strip().strip('"').strip("'")
        return normalized or None
    return None


def find_generated_installer() -> Path:
    candidates = sorted(
        DIST_DIR.glob("PlugAgente-Setup-*.exe"),
        key=lambda path: path.stat().st_mtime,
        reverse=True,
    )
    if not candidates:
        raise SystemExit(f"Erro: instalador nao encontrado em {DIST_DIR}")
    return candidates[0]


def signing_cert_path() -> Optional[Path]:
    value = os.environ.get("WINDOWS_CODE_SIGNING_CERT_PATH") or read_env_value(
        "WINDOWS_CODE_SIGNING_CERT_PATH"
    )
    if not value:
        return None
    return Path(value).expanduser()


def signing_password() -> Optional[str]:
    return os.environ.get("WINDOWS_CODE_SIGNING_CERT_PASSWORD") or read_env_value(
        "WINDOWS_CODE_SIGNING_CERT_PASSWORD"
    )


def timestamp_url() -> str:
    return (
        os.environ.get("WINDOWS_CODE_SIGNING_TIMESTAMP_URL")
        or read_env_value("WINDOWS_CODE_SIGNING_TIMESTAMP_URL")
        or DEFAULT_TIMESTAMP_URL
    )


def should_sign_artifacts() -> bool:
    return signing_cert_path() is not None or read_env_flag("WINDOWS_CODE_SIGNING_REQUIRED")


def auto_update_requires_valid_signature() -> bool:
    """Mirrors the Dart resolver `resolveAutoUpdateRequireValidSignature`:
    unset defaults to TRUE, and only an explicit falsy token disables it.

    Keeping this in lockstep with the runtime contract is what lets the build
    refuse to ship a self-bricking installer (see `ensure_signing_matches_runtime`).
    """
    value = resolve_auto_update_define("AUTO_UPDATE_REQUIRE_VALID_SIGNATURE")
    if value is None or not value.strip():
        return True
    return value.strip().lower() not in {"0", "false", "no", "nao"}


def ensure_signing_matches_runtime() -> None:
    """Fails fast when the build would embed `requireValidSignature=true` at
    runtime but does not Authenticode-sign the artifacts.

    Such a build produces an installer that the update helper refuses to run
    (it gates on a valid Authenticode signature), silently bricking every
    future auto-update. Operators building unsigned dev artifacts must opt out
    explicitly with `AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=false`.
    """
    if auto_update_requires_valid_signature() and not should_sign_artifacts():
        raise SystemExit(
            "Refusing to build: AUTO_UPDATE_REQUIRE_VALID_SIGNATURE resolves to "
            "true (the runtime default) but code signing is not configured, so "
            "the update helper would reject the resulting installer and break "
            "auto-update. Configure WINDOWS_CODE_SIGNING_CERT_PATH (or set "
            "WINDOWS_CODE_SIGNING_REQUIRED=true), or set "
            "AUTO_UPDATE_REQUIRE_VALID_SIGNATURE=false for unsigned dev builds."
        )


def sign_file(path: Path) -> None:
    cert_path = signing_cert_path()
    required = read_env_flag("WINDOWS_CODE_SIGNING_REQUIRED")
    if cert_path is None:
        if required:
            raise SystemExit("WINDOWS_CODE_SIGNING_REQUIRED=true, mas WINDOWS_CODE_SIGNING_CERT_PATH nao foi definido.")
        print(f"   Assinatura ignorada para {path.name}: certificado nao configurado.", flush=True)
        return
    if not cert_path.exists():
        raise SystemExit(f"Certificado de assinatura nao encontrado: {cert_path}")

    signtool = find_signtool()
    if signtool is None:
        raise SystemExit("signtool nao encontrado. Instale Windows SDK ou coloque signtool no PATH.")

    cmd = [
        signtool,
        "sign",
        "/f",
        str(cert_path),
        "/fd",
        "SHA256",
        "/tr",
        timestamp_url(),
        "/td",
        "SHA256",
    ]
    password = signing_password()
    if password:
        cmd.extend(["/p", password])
    cmd.append(str(path))
    run(cmd)
    run([signtool, "verify", "/pa", "/v", str(path)])


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Gera o instalador Windows (.exe) do Plug Agente.",
    )
    parser.add_argument(
        "--sync-version",
        action="store_true",
        help="Sincroniza a versao do pubspec.yaml antes do build (update_version.py).",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    ensure_signing_matches_runtime()

    step = 1
    if args.sync_version:
        print(f"{step}. Executando update_version.py...", flush=True)
        run([sys.executable, str(INSTALLER_DIR / "update_version.py")])
        step += 1

    print(f"\n{step}. Build Flutter (windows --release)...", flush=True)
    flutter_cmd = ["flutter", "build", "windows", "--release"]
    feed_url = resolve_auto_update_feed_url()
    if feed_url:
        flutter_cmd.append(f"--dart-define=AUTO_UPDATE_FEED_URL={feed_url}")
        print(f"   AUTO_UPDATE_FEED_URL injetado via --dart-define: {feed_url}", flush=True)
    else:
        print(
            "   AUTO_UPDATE_FEED_URL nao encontrado no .env; usando feed oficial padrao",
            flush=True,
        )
    for key in (
        "AUTO_UPDATE_CHANNEL",
        "AUTO_UPDATE_REQUIRE_VALID_SIGNATURE",
        "AUTO_UPDATE_FEED_PUBLIC_KEY",
        "AUTO_UPDATE_REQUIRE_FEED_SIGNATURE",
    ):
        value = resolve_auto_update_define(key)
        if value:
            flutter_cmd.append(f"--dart-define={key}={value}")
            print(f"   {key} injetado via --dart-define: {value}", flush=True)
    run(flutter_cmd)

    if not BUILD_DIR.exists():
        raise SystemExit(f"Erro: pasta de build nao encontrada: {BUILD_DIR}")

    step += 1
    print(f"\n{step}. Build elevated action runner helper...", flush=True)
    elevated_runner_script = PROJECT_ROOT / "tool" / "elevated" / "build_elevated_runner.py"
    if elevated_runner_script.exists():
        run([sys.executable, str(elevated_runner_script)])
    else:
        raise SystemExit("Erro: tool/elevated/build_elevated_runner.py nao encontrado")

    if not (BUILD_DIR / "plug_agente.exe").exists():
        raise SystemExit("Erro: plug_agente.exe nao encontrado no build")
    if not (BUILD_DIR / "plug_update_helper.exe").exists():
        raise SystemExit("Erro: plug_update_helper.exe nao encontrado no build")
    if not (BUILD_DIR / "plug_agente_elevated_runner.exe").exists():
        raise SystemExit(
            "Erro: plug_agente_elevated_runner.exe nao encontrado no build. "
            "Execute python tool/elevated/build_elevated_runner.py antes do instalador.",
        )

    app_exe = BUILD_DIR / "plug_agente.exe"
    helper_exe = BUILD_DIR / "plug_update_helper.exe"
    elevated_helper_exe = BUILD_DIR / "plug_agente_elevated_runner.exe"
    if should_sign_artifacts():
        step += 1
        print(f"\n{step}.1. Assinando executavel Windows...", flush=True)
        sign_file(app_exe)
        print(f"\n{step}.2. Assinando helper de update Windows...", flush=True)
        sign_file(helper_exe)
        print(f"\n{step}.3. Assinando elevated action runner...", flush=True)
        sign_file(elevated_helper_exe)

    step += 1
    print(f"\n{step}. Compilando instalador Inno Setup...", flush=True)
    iscc = find_iscc()
    run([iscc, str(SETUP_ISS)], cwd=INSTALLER_DIR)

    DIST_DIR.mkdir(parents=True, exist_ok=True)
    installer_path = find_generated_installer()
    if should_sign_artifacts():
        print(f"\n{step}.1. Assinando instalador Windows...", flush=True)
        sign_file(installer_path)
    print(f"\nInstalador gerado em: {installer_path}", flush=True)


if __name__ == "__main__":
    main()
