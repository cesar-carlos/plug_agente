"""Prepare the checksummed native release of the locked pub.dev package."""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import urljoin, urlparse
from urllib.request import url2pathname, urlopen

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tool.odbc.build_pinned_native import verify_native_bundle


def locked_package(root: Path) -> tuple[Path, str, str]:
    lock = (root / 'pubspec.lock').read_text(encoding='utf-8')
    block = re.search(r'^  odbc_fast:\n(.*?)(?=^  \w|^sdks:)', lock, re.M | re.S)
    if not block or 'source: hosted' not in block[1] or 'https://pub.dev' not in block[1]:
        raise ValueError('odbc_fast must be locked to its published pub.dev package')
    version = re.search(r'^    version: "([0-9]+\.[0-9]+\.[0-9]+(?:[-+][0-9A-Za-z.-]+)?)"', block[1], re.M)
    digest = re.search(r'^      sha256: ["\']?([0-9a-f]{64})', block[1], re.M)
    if not version or not digest:
        raise ValueError('The hosted lock must contain the exact version and package SHA-256')
    config = root / '.dart_tool/package_config.json'
    packages = json.loads(config.read_text(encoding='utf-8'))['packages']
    uri = next(p['rootUri'] for p in packages if p['name'] == 'odbc_fast')
    package = Path(url2pathname(urlparse(urljoin(config.resolve().as_uri(), uri)).path))
    actual = re.search(r'^version:\s*(\S+)', (package / 'pubspec.yaml').read_text(encoding='utf-8'), re.M)
    if not actual or actual[1] != version[1]:
        raise ValueError('Resolved package version differs from pubspec.lock')
    return package, version[1], digest[1]


def download(url: str, destination: Path, limit: int) -> None:
    size = 0
    with urlopen(url, timeout=60) as response, destination.open('wb') as output:
        while chunk := response.read(65536):
            size += len(chunk)
            if size > limit:
                raise ValueError('Published native asset exceeds its size limit')
            output.write(chunk)


def checksum(path: Path) -> str:
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def prepare_native_library(root: Path = ROOT) -> Path:
    root = root.resolve()
    _, version, package_digest = locked_package(root)
    platform = 'windows_x64' if os.name == 'nt' else 'linux_x64'
    name = 'odbc_engine.dll' if os.name == 'nt' else 'libodbc_engine.so'
    directory = root / 'build/odbc-native/packages' / version / platform
    directory.mkdir(parents=True, exist_ok=True)
    binary = directory / name
    manifest = directory / 'manifest.json'
    url = f'https://github.com/cesar-carlos/dart_odbc_fast/releases/download/v{version}/{name}'
    if binary.exists() and manifest.exists():
        record = json.loads(manifest.read_text(encoding='utf-8'))
        if (record.get('version') != version or record.get('package_sha256') != package_digest or
                record.get('url') != url or record.get('sha256') != checksum(binary)):
            raise ValueError('Cached published native asset differs from its manifest')
        return binary.resolve()
    temporary = directory / (name + '.part')
    sidecar = directory / (name + '.sha256.part')
    try:
        download(url + '.sha256', sidecar, 4096)
        fields = sidecar.read_text(encoding='utf-8').strip().split()
        if not fields or not re.fullmatch('[0-9a-fA-F]{64}', fields[0]):
            raise ValueError('Published native asset checksum is invalid')
        expected = fields[0].lower()
        download(url, temporary, 128 * 1024 * 1024)
        if checksum(temporary) != expected:
            raise ValueError('Published native asset SHA-256 mismatch')
        temporary.replace(binary)
        manifest.write_text(json.dumps({
            'source': 'pub.dev', 'version': version, 'package_sha256': package_digest,
            'url': url, 'sha256': expected,
        }, indent=2), encoding='utf-8')
    finally:
        temporary.unlink(missing_ok=True)
        sidecar.unlink(missing_ok=True)
    return binary.resolve()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=ROOT)
    parser.add_argument('--github-env', type=Path)
    parser.add_argument('--verify-bundle', type=Path)
    args = parser.parse_args()
    binary = prepare_native_library(args.root)
    if args.verify_bundle:
        verify_native_bundle(args.verify_bundle, binary)
    print(f'Published odbc_fast native asset: {binary}')
    if args.github_env:
        with args.github_env.open('a', encoding='utf-8') as output:
            output.write(f'ODBC_FAST_NATIVE_LIBRARY={binary}\n')


if __name__ == '__main__':
    main()
