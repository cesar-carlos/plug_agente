"""Prepare native artifacts and qualify an intentional dependency update."""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tool.odbc.build_pinned_native import build_pinned_native, build_source_native
from tool.odbc.prepare_package_native import prepare_native_library
from tool.py.script_utils import resolve_command


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base-dir', type=Path, required=True)
    parser.add_argument('--output-dir', type=Path, required=True)
    parser.add_argument('--hosted-baseline-revision', help='Explicit Git source of the legacy hosted engine')
    parser.add_argument('--baseline-repository', type=Path, help='Reuse an existing native Git repository')
    args = parser.parse_args()
    base = args.base_dir.resolve()
    subprocess.run(resolve_command(['flutter', 'pub', 'get']), cwd=base, check=True)
    lock = (base / 'pubspec.lock').read_text(encoding='utf-8')
    block = re.search(r'^  odbc_fast:\n(.*?)(?=^  \w|^sdks:)', lock, re.M | re.S)
    if block and 'source: git' in block[1]:
        baseline = build_pinned_native(base)
    else:
        revision = args.hosted_baseline_revision
        if not revision or not re.fullmatch('[0-9a-f]{40}', revision):
            parser.error('A hosted baseline requires its explicit full native Git revision')
        checkout = args.baseline_repository or ROOT / 'build/transport-native-baseline'
        if args.baseline_repository and not checkout.is_dir():
            parser.error('The explicit baseline repository must already exist')
        if not checkout.exists():
            subprocess.run(['git', 'clone', '--no-checkout', 'https://github.com/cesar-carlos/dart_odbc_fast.git', str(checkout)], check=True)
        subprocess.run(['git', '-C', str(checkout), 'fetch', 'origin', revision], check=True)
        source_pubspec = subprocess.check_output(['git', '-C', str(checkout), 'show', f'{revision}:pubspec.yaml'], text=True)
        version = re.search(r'^version:\s*(\S+)', source_pubspec, re.M)
        if not block or not version or f'version: "{version[1]}"' not in block[1]:
            raise ValueError('Hosted package version differs from the explicit Git baseline')
        baseline = build_source_native(base, checkout, revision)
    candidate = prepare_native_library(ROOT)
    baseline_revision = json.loads((baseline.parent / 'manifest.json').read_text())['revision']
    return subprocess.run([sys.executable, str(ROOT / 'tool/benchmarks/run_transport_comparison.py'),
        '--base-dir', str(base), '--output-dir', str(args.output_dir), '--allow-odbc-change',
        '--base-native-library', str(baseline), '--candidate-native-library', str(candidate),
        '--base-odbc-revision', baseline_revision], cwd=ROOT).returncode


if __name__ == '__main__':
    raise SystemExit(main())
