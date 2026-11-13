"""Bind independent release jobs to the same versioned Git tree."""
from __future__ import annotations

import os
import hashlib
from pathlib import Path
import re
import subprocess
import sys


VERSION_PATHS = ('pubspec.yaml', 'installer/setup.iss', 'lib/core/constants/app_version.g.dart')


def prepare(root: Path, full_version: str) -> str:
    if not re.fullmatch(r'\d+\.\d+\.\d+\+\d+', full_version):
        raise ValueError('Invalid FULL_VERSION')
    subprocess.run(['git', 'diff', '--exit-code', 'HEAD', '--'], cwd=root, check=True)
    path = root / 'pubspec.yaml'
    content, count = re.subn(
        r'^version:\s*["\']?\d+\.\d+\.\d+(?:\+\d+)?["\']?\s*(?:#|$)',
        f'version: {full_version}', path.read_text(encoding='utf-8'),
        count=1, flags=re.MULTILINE,
    )
    if count != 1:
        raise ValueError('Unable to update pubspec.yaml version')
    path.write_text(content, encoding='utf-8')
    subprocess.run([sys.executable, 'installer/update_version.py'], cwd=root, check=True)
    subprocess.run(['git', 'add', '--', *VERSION_PATHS], cwd=root, check=True)
    return subprocess.check_output(['git', 'write-tree'], cwd=root, text=True).strip()


def require_tree(actual: str, expected: str) -> None:
    if not expected or actual != expected:
        raise ValueError('Prepared source differs from the tested/built source tree')


def verify_installer(path: Path, expected: str) -> None:
    with path.open('rb') as stream:
        actual = hashlib.file_digest(stream, 'sha256').hexdigest()
    if not expected or actual != expected:
        raise ValueError('Prepared installer digest mismatch')


if __name__ == '__main__':
    if sys.argv[1:] == ['--verify-installer']:
        verify_installer(
            Path('installer/dist') / f"PlugAgente-Setup-{os.environ['VERSION_SHORT']}.exe",
            os.environ['EXPECTED_SHA256'],
        )
        sys.exit(0)
    tree = prepare(Path.cwd(), os.environ['FULL_VERSION'])
    if 'EXPECTED_SOURCE_TREE' in os.environ:
        require_tree(tree, os.environ['EXPECTED_SOURCE_TREE'])
    if os.environ.get('GITHUB_OUTPUT'):
        with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
            output.write(f'tree={tree}\n')
    print(f'Prepared source tree: {tree}')
