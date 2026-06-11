#!/usr/bin/env python3
from __future__ import annotations

import subprocess
import sys
import time
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
EXE_DEBUG = PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Debug" / "plug_agente.exe"
EXE_RELEASE = PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Release" / "plug_agente.exe"


def resolve_executable() -> Path:
    if EXE_DEBUG.is_file():
        return EXE_DEBUG
    if EXE_RELEASE.is_file():
        return EXE_RELEASE
    print("Nenhum executável encontrado. Execute 'flutter build windows' primeiro.", file=sys.stderr)
    raise SystemExit(1)


def stop_existing_processes() -> None:
    subprocess.run(
        ["taskkill", "/F", "/IM", "plug_agente.exe"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )


def start_process(exe: Path, *args: str) -> subprocess.Popen[bytes]:
    return subprocess.Popen(
        [str(exe), *args],
        cwd=PROJECT_ROOT,
        creationflags=subprocess.CREATE_NEW_CONSOLE if sys.platform == "win32" else 0,
    )


def process_running(process: subprocess.Popen[bytes]) -> bool:
    return process.poll() is None


def main() -> int:
    exe = resolve_executable()
    print(f"Usando: {exe}")
    print()

    stop_existing_processes()
    time.sleep(2)

    print("Cenário 1: Abrir app normalmente...")
    first = start_process(exe)
    time.sleep(3)

    print("Cenário 1: Tentar abrir segunda instância (manual)...")
    second = start_process(exe)
    time.sleep(2)

    if process_running(second):
        print("AVISO: Segunda instância ainda está rodando. Verifique se a MessageBox foi exibida.")
    else:
        print("OK: Segunda instância encerrou (MessageBox deve ter sido exibida).")

    print()
    print("Cenário 2: Tentar abrir com --autostart...")
    third = start_process(exe, "--autostart")
    time.sleep(2)

    if process_running(third):
        print("AVISO: Terceira instância (--autostart) ainda está rodando. Deveria ter encerrado silenciosamente.")
        third.kill()
    else:
        print("OK: Instância --autostart encerrou silenciosamente.")

    print()
    print("Encerrando primeira instância...")
    if process_running(first):
        first.kill()
    time.sleep(1)

    print("Teste concluído. Revise os resultados acima.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
