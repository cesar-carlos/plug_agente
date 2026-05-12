#!/usr/bin/env python3
"""
Orquestra o build do instalador Windows: sincroniza versao, build Flutter e
compila Inno Setup.

Fluxo: update_version.py -> flutter build windows --release -> ISCC setup.iss

Saida: installer/dist/PlugAgente-Setup-{versao}.exe

Requisitos: Flutter no PATH, Inno Setup 6 (ISCC no PATH ou em Program Files).
Execute a partir da raiz: python installer/build_installer.py
"""

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
    return read_env_value("AUTO_UPDATE_FEED_URL")


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


def main() -> None:
    print("1. Executando update_version.py...", flush=True)
    run([sys.executable, str(INSTALLER_DIR / "update_version.py")])

    print("\n2. Build Flutter (windows --release)...", flush=True)
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
    run(flutter_cmd)

    if not BUILD_DIR.exists():
        raise SystemExit(f"Erro: pasta de build nao encontrada: {BUILD_DIR}")

    if not (BUILD_DIR / "plug_agente.exe").exists():
        raise SystemExit("Erro: plug_agente.exe nao encontrado no build")

    app_exe = BUILD_DIR / "plug_agente.exe"
    if should_sign_artifacts():
        print("\n2.1. Assinando executavel Windows...", flush=True)
        sign_file(app_exe)

    print("\n3. Compilando instalador Inno Setup...", flush=True)
    iscc = find_iscc()
    run([iscc, str(SETUP_ISS)], cwd=INSTALLER_DIR)

    DIST_DIR.mkdir(parents=True, exist_ok=True)
    installer_path = find_generated_installer()
    if should_sign_artifacts():
        print("\n3.1. Assinando instalador Windows...", flush=True)
        sign_file(installer_path)
    print(f"\nInstalador gerado em: {installer_path}", flush=True)


if __name__ == "__main__":
    main()
