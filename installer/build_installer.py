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
import base64
import binascii
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import List, Optional, Sequence

PROJECT_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(PROJECT_ROOT))
from tool.odbc.prepare_package_native import prepare_native_library, verify_native_bundle
from tool.release.windows_version_info import application_version, set_version_info
INSTALLER_DIR = PROJECT_ROOT / "installer"
BUILD_DIR = PROJECT_ROOT / "build" / "windows" / "x64" / "runner" / "Release"
SETUP_ISS = INSTALLER_DIR / "setup.iss"
DIST_DIR = INSTALLER_DIR / "dist"
ENV_FILE = PROJECT_ROOT / ".env"
DEFAULT_TIMESTAMP_URL = "http://timestamp.digicert.com"
REQUIRED_VC_RUNTIME_DLLS = ("msvcp140.dll", "vcruntime140.dll", "vcruntime140_1.dll")
PROJECT_EXECUTABLES = (
    "plug_agente.exe", "plug_update_helper.exe", "plug_install_check.exe",
    "plug_agente_elevated_runner.exe", "updater/plug_update_service.exe",
    "updater/plug_update_client.exe", "updater/plug_update_worker.exe",
)

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


def configure_native_feed_keys() -> Optional[str]:
    value = resolve_auto_update_define("AUTO_UPDATE_FEED_PUBLIC_KEY")
    if not value or not value.strip():
        if should_sign_artifacts():
            raise SystemExit(
                "Refusing to build a signed installer without AUTO_UPDATE_FEED_PUBLIC_KEY. "
                "Configure the feed signing public key before rebuilding; otherwise "
                "updater enrollment fails with feed_keys_unavailable."
            )
        return None
    keys = [part.strip() for part in value.split(",")]
    for key in keys:
        try:
            decoded = base64.b64decode(key, validate=True)
        except (ValueError, binascii.Error) as error:
            raise SystemExit("AUTO_UPDATE_FEED_PUBLIC_KEY must contain base64 Ed25519 public keys.") from error
        if len(decoded) != 32:
            raise SystemExit("AUTO_UPDATE_FEED_PUBLIC_KEY entries must decode to 32 bytes.")
    normalized = ",".join(keys)
    os.environ["AUTO_UPDATE_FEED_PUBLIC_KEY"] = normalized
    return normalized


def verify_native_feed_keys(keys: Optional[str]) -> None:
    if not keys:
        return
    client = BUILD_DIR / "updater" / "plug_update_client.exe"
    if not client.is_file() or keys.encode("ascii") + b"\0" not in client.read_bytes():
        raise SystemExit(
            "Native updater is missing the configured AUTO_UPDATE_FEED_PUBLIC_KEY. "
            "Rebuild the Windows bundle with the feed public keys available to CMake "
            "before packaging the installer."
        )


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
    version = re.search(r'^#define MyAppVersion "([0-9]+\.[0-9]+\.[0-9]+)"$', SETUP_ISS.read_text(encoding="utf-8"), re.MULTILINE)
    if version is None:
        raise SystemExit("Invalid installer version")
    expected = DIST_DIR / f"PlugAgente-Setup-{version.group(1)}.exe"
    if not expected.is_file():
        raise SystemExit(f"Erro: instalador esperado nao encontrado: {expected.name}")
    return expected


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


def build_iscc_signtool_command() -> Optional[str]:
    cert_path = signing_cert_path()
    if cert_path is None:
        return None
    if not cert_path.exists():
        raise SystemExit(f"Certificado de assinatura nao encontrado: {cert_path}")
    signtool = find_signtool()
    if signtool is None:
        raise SystemExit(
            "signtool nao encontrado. Instale Windows SDK ou coloque signtool no PATH."
        )
    command = (
        f'"{signtool}" sign /f "{cert_path}" /fd SHA256 /tr {timestamp_url()} '
        f"/td SHA256"
    )
    password = signing_password()
    if password:
        command += f' /p "{password}"'
    command += " $f"
    return command


def verify_bundled_vc_runtime() -> None:
    missing = [
        name for name in REQUIRED_VC_RUNTIME_DLLS
        if not (BUILD_DIR / name).is_file() or (BUILD_DIR / name).stat().st_size == 0
    ]
    if missing:
        raise SystemExit(
            "Visual C++ runtime missing from the application bundle: " + ", ".join(missing)
            + ". Rebuild Windows with the Visual Studio C++ redistributable components installed."
        )


def verify_bundled_fonts() -> None:
    assets = BUILD_DIR / "data/flutter_assets"
    manifest = json.loads((assets / "FontManifest.json").read_text(encoding="utf-8"))
    registered = {font["asset"] for family in manifest if family.get("family") == "Montserrat"
                  for font in family.get("fonts", [])}
    for name in ("Montserrat.ttf", "Montserrat-Italic.ttf"):
        relative = f"assets/fonts/montserrat/{name}"
        bundled = assets / relative
        source = PROJECT_ROOT / relative
        if relative not in registered or not bundled.is_file() or hashlib.sha256(bundled.read_bytes()).digest() != hashlib.sha256(source.read_bytes()).digest():
            raise SystemExit(f"Bundled Montserrat font is missing or stale: {name}. Check flutter.fonts in pubspec.yaml.")


def prepare_privacy_notice() -> Path:
    readme = (PROJECT_ROOT / "readme.md").read_bytes()
    text = readme.decode("utf-16-le") if b"\0" in readme[:100] else readme.decode("utf-8")
    heading = "## Privacy policy"
    if heading not in text:
        raise SystemExit("Installer requires the project's privacy policy")
    notice = DIST_DIR / "privacy-notice.txt"
    notice.parent.mkdir(parents=True, exist_ok=True)
    notice.write_text(text.split(heading, 1)[1].split("\n## ", 1)[0].strip() + "\n", encoding="utf-8-sig")
    return notice


def build_iscc_command(*, signed_uninstaller_dir: Optional[Path] = None) -> List[str]:
    cmd = [find_iscc()]
    pubspec = (PROJECT_ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    version = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+\+[0-9]+)\s*$', pubspec, re.MULTILINE)
    if version is None:
        raise SystemExit('Installer worker requires the exact application version including build number')
    setup_version = re.search(r'^#define MyAppVersion "([0-9]+\.[0-9]+\.[0-9]+)"$', SETUP_ISS.read_text(encoding="utf-8"), re.MULTILINE)
    if setup_version is None or setup_version.group(1) != version.group(1).split("+", 1)[0]:
        raise SystemExit("Installer version differs from pubspec.yaml; run installer/update_version.py")
    cmd.append(f'/DMyAppWorkerVersion={version.group(1)}')
    channel = resolve_auto_update_define("AUTO_UPDATE_CHANNEL") or "stable"
    if channel not in {"stable", "beta", "internal"}:
        raise SystemExit("Invalid installer update channel")
    cmd.append(f"/DMyAppChannel={channel}")
    cmd.append(f"/DPrivacyNoticeFile={prepare_privacy_notice()}")
    sign_command = None if signed_uninstaller_dir is not None else build_iscc_signtool_command()
    if signed_uninstaller_dir is not None:
        cmd.append(f"/DExternalSignedUninstallerDir={signed_uninstaller_dir}")
    if sign_command is not None:
        cmd.append("/DSIGN_INSTALLER")
        cmd.append(f"/Smysigntool={sign_command}")
        print("   ISCC SignTool habilitado (SignedUninstaller).", flush=True)
    cmd.append(str(SETUP_ISS))
    return cmd


def verify_signed_file(path: Path) -> None:
    signtool = find_signtool()
    if signtool is None:
        raise SystemExit(
            "signtool nao encontrado. Instale Windows SDK ou coloque signtool no PATH."
        )
    run([signtool, "verify", "/pa", "/v", str(path)])


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
    verify_signed_file(path)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Gera o instalador Windows (.exe) do Plug Agente.",
    )
    parser.add_argument(
        "--sync-version",
        action="store_true",
        help="Sincroniza a versao do pubspec.yaml antes do build (update_version.py).",
    )
    parser.add_argument("--prepare-signpath", action="store_true",
                        help="Build trusted unsigned inputs for the staged SignPath workflow.")
    parser.add_argument("--manifest-only", action="store_true",
                        help="Require Ed25519 feed/manifest authentication without an Authenticode certificate.")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if args.manifest_only:
        if args.prepare_signpath or signing_cert_path() is not None:
            raise SystemExit("Manifest-only mode cannot use SignPath or a local signing certificate")
        os.environ["AUTO_UPDATE_REQUIRE_VALID_SIGNATURE"] = "false"
        os.environ["AUTO_UPDATE_REQUIRE_FEED_SIGNATURE"] = "true"
        os.environ["WINDOWS_CODE_SIGNING_REQUIRED"] = "false"
    if args.prepare_signpath:
        if signing_cert_path() is not None:
            raise SystemExit("SignPath preparation cannot use a local signing certificate")
        os.environ["WINDOWS_CODE_SIGNING_REQUIRED"] = "true"
    ensure_signing_matches_runtime()
    feed_keys = configure_native_feed_keys()
    if args.manifest_only and not feed_keys:
        raise SystemExit("Manifest-only updates require the Ed25519 feed public key")
    # CMake does not read .env. Keep the native enrollment policy and Dart in sync.
    os.environ["AUTO_UPDATE_REQUIRE_VALID_SIGNATURE"] = "true" if auto_update_requires_valid_signature() else "false"
    run(["flutter", "pub", "get"])
    os.environ['ODBC_FAST_NATIVE_LIBRARY'] = str(prepare_native_library(PROJECT_ROOT))

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
    verify_bundled_vc_runtime()
    verify_bundled_fonts()
    verify_native_feed_keys(feed_keys)
    native = Path(os.environ['ODBC_FAST_NATIVE_LIBRARY'])
    verify_native_bundle(BUILD_DIR, native)
    shutil.copy2(native.parent / 'manifest.json', BUILD_DIR / 'data/odbc_native_manifest.json')

    step += 1
    print(f"\n{step}. Build elevated action runner helper...", flush=True)
    elevated_runner_script = PROJECT_ROOT / "tool" / "elevated" / "build_elevated_runner.py"
    if elevated_runner_script.exists():
        run([sys.executable, str(elevated_runner_script), '--release-only'])
    else:
        raise SystemExit("Erro: tool/elevated/build_elevated_runner.py nao encontrado")

    if not (BUILD_DIR / "plug_agente.exe").exists():
        raise SystemExit("Erro: plug_agente.exe nao encontrado no build")
    if not (BUILD_DIR / "plug_update_helper.exe").exists():
        raise SystemExit("Erro: plug_update_helper.exe nao encontrado no build")
    if not (BUILD_DIR / "plug_install_check.exe").exists():
        raise SystemExit("Erro: plug_install_check.exe nao encontrado no build")
    if not (BUILD_DIR / "plug_agente_elevated_runner.exe").exists():
        raise SystemExit(
            "Erro: plug_agente_elevated_runner.exe nao encontrado no build. "
            "Execute python tool/elevated/build_elevated_runner.py antes do instalador.",
        )

    for name in PROJECT_EXECUTABLES:
        set_version_info(BUILD_DIR / name, application_version())
    run([str(BUILD_DIR / "plug_agente_elevated_runner.exe"), "--help"])
    if args.prepare_signpath:
        from installer.signpath_staging import prepare
        try:
            prepare()
        except (OSError, ValueError, subprocess.SubprocessError) as error:
            raise SystemExit(f"SignPath preparation failed: {error}") from error
        return

    app_exe = BUILD_DIR / "plug_agente.exe"
    helper_exe = BUILD_DIR / "plug_update_helper.exe"
    elevated_helper_exe = BUILD_DIR / "plug_agente_elevated_runner.exe"
    updater_artifacts = [BUILD_DIR / "updater" / name for name in (
        "plug_update_service.exe", "plug_update_client.exe", "plug_update_worker.exe")]
    for artifact in updater_artifacts:
        if not artifact.exists():
            raise SystemExit(f"Updater artifact missing: {artifact.name}")
    if should_sign_artifacts():
        step += 1
        print(f"\n{step}.1. Assinando executavel Windows...", flush=True)
        sign_file(app_exe)
        print(f"\n{step}.2. Assinando helper de update Windows...", flush=True)
        sign_file(helper_exe)
        sign_file(BUILD_DIR / "plug_install_check.exe")
        print(f"\n{step}.3. Assinando elevated action runner...", flush=True)
        sign_file(elevated_helper_exe)
        for artifact in updater_artifacts:
            sign_file(artifact)

    step += 1
    print(f"\n{step}. Compilando instalador Inno Setup...", flush=True)
    run(build_iscc_command(), cwd=INSTALLER_DIR)

    DIST_DIR.mkdir(parents=True, exist_ok=True)
    installer_path = find_generated_installer()
    if should_sign_artifacts() and signing_cert_path() is not None:
        print(f"\n{step}.1. Verificando assinatura do instalador Windows...", flush=True)
        verify_signed_file(installer_path)
    print(f"\nInstalador gerado em: {installer_path}", flush=True)


if __name__ == "__main__":
    main()
