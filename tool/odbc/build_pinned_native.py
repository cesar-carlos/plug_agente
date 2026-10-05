"""Build the locked Git engine in the workspace, without writing to Pub cache."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import re
import subprocess
import sys
import tarfile
from pathlib import Path
from urllib.parse import urljoin
from urllib.request import url2pathname

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tool.py.script_utils import resolve_command


def pinned_package(root: Path) -> tuple[Path, str]:
    lock = (root / 'pubspec.lock').read_text(encoding='utf-8')
    block = re.search(r'^  odbc_fast:\n(.*?)(?=^  \w|^sdks:)', lock, re.M | re.S)
    revision = re.search(r'resolved-ref: ["\']?([0-9a-f]{40})', block[1] if block else '')
    if not revision or 'source: git' not in block[1]:
        raise ValueError('odbc_fast must be locked to a full Git revision')
    config = root / '.dart_tool/package_config.json'
    packages = json.loads(config.read_text(encoding='utf-8'))['packages']
    uri = next(p['rootUri'] for p in packages if p['name'] == 'odbc_fast')
    from urllib.parse import urlparse
    package = Path(url2pathname(urlparse(urljoin(config.as_uri(), uri)).path))
    actual = subprocess.check_output(['git', '-C', str(package), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != revision[1]:
        raise ValueError('Resolved package checkout differs from pubspec.lock')
    return package, actual


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def stage_for_hook(root: Path, binary: Path) -> Path:
    import shutil
    destination = root / 'build/odbc-native/pinned'
    destination.mkdir(parents=True, exist_ok=True)
    artifact = destination / binary.name
    if not artifact.exists() or sha256(artifact) != sha256(binary):
        shutil.copy2(binary, artifact)
    shutil.copy2(binary.parent / 'manifest.json', destination / 'manifest.json')
    return binary.resolve()


def verify_native_bundle(bundle: Path, binary: Path) -> None:
    matches = list(bundle.rglob(binary.name))
    if not matches or any(sha256(path) != sha256(binary) for path in matches):
        raise ValueError('Flutter bundle does not contain the locked native artifact')


def build_pinned_native(root: Path = ROOT) -> Path:
    package, revision = pinned_package(root.resolve())
    if not (package / 'native/Cargo.lock').is_file():
        raise ValueError('Pinned native source must contain its tracked Cargo.lock')
    return build_source_native(root, package, revision)


def build_source_native(root: Path, package: Path, revision: str) -> Path:
    directory = root / 'build/odbc-native' / revision
    binary = directory / ('odbc_engine.dll' if os.name == 'nt' else 'libodbc_engine.so')
    manifest = directory / 'manifest.json'
    if binary.exists() and manifest.exists():
        provenance = json.loads(manifest.read_text(encoding='utf-8'))
        if provenance['revision'] == revision and provenance['sha256'] == sha256(binary):
            return stage_for_hook(root, binary)
        raise ValueError('Existing native artifact differs from its manifest')
    directory.mkdir(parents=True, exist_ok=True)
    source = directory / 'source'
    source.mkdir(exist_ok=True)
    archive = subprocess.check_output(['git', '-C', str(package), 'archive', revision])
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        tree.extractall(source, filter='data')
    locked_dependencies = (source / 'native/Cargo.lock').is_file()
    command = resolve_command(['cargo', 'build', '-p', 'odbc_engine', '--release',
                               *(['--locked'] if locked_dependencies else [])])
    print(f'Building odbc_fast {revision}', flush=True)
    with (directory / 'build.log').open('w', encoding='utf-8') as log:
        result = subprocess.run(command, cwd=source / 'native', stdout=log, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f'Native build failed; see {directory / "build.log"}')
    import shutil
    shutil.copy2(source / 'native/target/release' / binary.name, binary)
    shutil.copy2(source / 'native/Cargo.lock', directory / 'Cargo.lock')
    provenance = {'revision': revision, 'sha256': sha256(binary),
                  'cargo_lock_sha256': sha256(source / 'native/Cargo.lock'),
                  'locked_dependencies': locked_dependencies,
                  'rustc': subprocess.check_output(['rustc', '--version'], cwd=source, text=True).strip()}
    manifest.write_text(json.dumps(provenance, indent=2), encoding='utf-8')
    return stage_for_hook(root, binary)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--github-env', type=Path)
    parser.add_argument('--verify-bundle', type=Path)
    args = parser.parse_args()
    binary = build_pinned_native(args.root)
    if args.verify_bundle:
        verify_native_bundle(args.verify_bundle, binary)
    print(f'ODBC_FAST_NATIVE_LIBRARY={binary}')
    if args.github_env:
        with args.github_env.open('a', encoding='utf-8') as output:
            output.write(f'ODBC_FAST_NATIVE_LIBRARY={binary}\n')


if __name__ == '__main__':
    main()
