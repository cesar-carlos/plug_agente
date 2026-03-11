#!/usr/bin/env python3
"""
Sincroniza a versão do pubspec.yaml em setup.iss e .env.
Execute a partir da raiz do projeto: python installer/update_version.py
"""

import re
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parent.parent
PUBSPEC = PROJECT_ROOT / "pubspec.yaml"
SETUP_ISS = PROJECT_ROOT / "installer" / "setup.iss"
ENV_FILE = PROJECT_ROOT / ".env"
ENV_EXAMPLE = PROJECT_ROOT / ".env.example"


def get_version_from_pubspec() -> str:
    content = PUBSPEC.read_text(encoding="utf-8")
    match = re.search(r'^version:\s*["\']?([\d.]+)', content, re.MULTILINE)
    if not match:
        raise SystemExit("Erro: versão não encontrada em pubspec.yaml")
    return match.group(1).strip()


def update_setup_iss(version: str) -> None:
    content = SETUP_ISS.read_text(encoding="utf-8")
    new_content = re.sub(
        r'#define MyAppVersion\s+".*"',
        f'#define MyAppVersion "{version}"',
        content,
    )
    SETUP_ISS.write_text(new_content, encoding="utf-8")
    print(f"  setup.iss: MyAppVersion = {version}")


def update_env(version: str) -> None:
    feed_url = "https://raw.githubusercontent.com/cesar-carlos/plug_agente/main/appcast.xml"
    if ENV_FILE.exists():
        content = ENV_FILE.read_text(encoding="utf-8")
        if "AUTO_UPDATE_FEED_URL" in content:
            content = re.sub(
                r"AUTO_UPDATE_FEED_URL=.*",
                f"AUTO_UPDATE_FEED_URL={feed_url}",
                content,
            )
        else:
            content = content.rstrip() + f"\nAUTO_UPDATE_FEED_URL={feed_url}\n"
        ENV_FILE.write_text(content, encoding="utf-8")
    else:
        ENV_FILE.write_text(f"AUTO_UPDATE_FEED_URL={feed_url}\n", encoding="utf-8")
    print(f"  .env: AUTO_UPDATE_FEED_URL atualizado")


def main() -> None:
    version = get_version_from_pubspec()
    print(f"Versão do pubspec.yaml: {version}")
    update_setup_iss(version)
    update_env(version)
    print("Sincronização concluída.")


if __name__ == "__main__":
    main()
