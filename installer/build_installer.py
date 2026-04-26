#!/usr/bin/env python3
"""
Orquestra o build do instalador Windows: sincroniza versão, build Flutter e compila Inno Setup.

Fluxo: update_version.py → flutter build windows --release → ISCC setup.iss

Saída: installer/dist/PlugAgente-Setup-{versão}.exe

Requisitos: Flutter no PATH, Inno Setup 6 (ISCC no PATH ou em Program Files).
Execute a partir da raiz: python installer/build_installer.py
"""

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

ISCC_PATHS = [
    "ISCC",
    r"C:\Program Files (x86)\Inno Setup 6\ISCC.exe",
    r"C:\Program Files\Inno Setup 6\ISCC.exe",
]


def find_iscc() -> str:
    for path in ISCC_PATHS:
        if path == "ISCC":
            if shutil.which("ISCC"):
                return "ISCC"
        elif Path(path).exists():
            return path
    raise SystemExit(
        "Inno Setup (ISCC) não encontrado. Instale em "
        "https://jrsoftware.org/isinfo.php"
    )


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
        raise SystemExit(f"Comando não encontrado: {executable}") from error
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode) from error


def resolve_auto_update_feed_url() -> Optional[str]:
    if not ENV_FILE.exists():
        return None

    for raw_line in ENV_FILE.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        if key.strip() != "AUTO_UPDATE_FEED_URL":
            continue
        normalized = value.strip().strip('"').strip("'")
        return normalized or None
    return None


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
        print("   Aviso: AUTO_UPDATE_FEED_URL não encontrado no .env", flush=True)
    run(flutter_cmd)

    if not BUILD_DIR.exists():
        raise SystemExit(f"Erro: pasta de build não encontrada: {BUILD_DIR}")

    if not (BUILD_DIR / "plug_agente.exe").exists():
        raise SystemExit("Erro: plug_agente.exe não encontrado no build")

    print("\n3. Compilando instalador Inno Setup...", flush=True)
    iscc = find_iscc()
    run([iscc, str(SETUP_ISS)], cwd=INSTALLER_DIR)

    DIST_DIR.mkdir(parents=True, exist_ok=True)
    print(f"\nInstalador gerado em: {DIST_DIR}", flush=True)


if __name__ == "__main__":
    main()
