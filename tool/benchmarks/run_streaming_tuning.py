"""Qualify driver-specific streaming settings; never change production defaults."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import statistics
import subprocess
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from tool.py.benchmark_common import bootstrap_env, ensure_on_path, collect_machine_metadata, collect_source_identity
from tool.py.script_utils import resolve_command
from tool.benchmarks.measurement_guard import MeasurementGuard, native_identity, file_set_identity
from tool.odbc.build_pinned_native import build_pinned_native, pinned_package


def metrics(report):
    samples = report['samples']
    if len(samples) != 9:
        raise ValueError('Nine samples required')
    return {'throughput': statistics.median(s['rows_per_second'] for s in samples),
            'first_p95_us': sorted(s['first_chunk_us'] for s in samples)[-1],
            'rss_peak_bytes': max(s['rss_peak_bytes'] for s in samples)}


def select_configuration(reports):
    baselines = {r['rows']: metrics(r) for r in reports if (r['fetch_size'], r['buffer_bytes']) == (1000, 1048576)}
    if set(baselines) != {1000, 8000, 50000}:
        raise ValueError('All three baseline workloads required')
    accepted = []
    for fetch in (1000, 2000, 4000, 8000):
        for buffer in (65536, 262144, 1048576):
            workloads = [r for r in reports if (r['fetch_size'], r['buffer_bytes']) == (fetch, buffer)]
            if {r['rows'] for r in workloads} != set(baselines):
                continue
            ratios = []
            for r in workloads:
                measured, base = metrics(r), baselines[r['rows']]
                ratios.append(measured['throughput'] / base['throughput'])
                if measured['first_p95_us'] > base['first_p95_us'] * 1.05 or measured['rss_peak_bytes'] > base['rss_peak_bytes'] * 1.1:
                    break
            else:
                gain = statistics.median(ratios)
                if min(ratios) >= 0.85 and gain >= 1.1:
                    accepted.append((gain, fetch, buffer))
    accepted.sort(key=lambda c: (-c[0], c[1], c[2]))
    return {'eligible': [{'throughput_ratio': g, 'fetch_size': f, 'buffer_bytes': b} for g, f, b in accepted],
            'recommendation': None if not accepted else {'fetch_size': accepted[0][1], 'buffer_bytes': accepted[0][2]}}


def control_stable(before, after):
    a, b = metrics(before), metrics(after)
    return (abs(b['throughput'] / a['throughput'] - 1) <= 0.15
            and abs(b['first_p95_us'] / a['first_p95_us'] - 1) <= 0.05
            and abs(b['rss_peak_bytes'] / a['rss_peak_bytes'] - 1) <= 0.1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument('--output-dir', type=Path, required=True)
    args = parser.parse_args()
    ensure_on_path()
    bootstrap_env(Path(__file__).resolve().parents[2] / '.env')
    args.output_dir.mkdir(parents=True, exist_ok=True)
    library = build_pinned_native(args.root)
    _, revision = pinned_package(args.root)
    identity = collect_source_identity(args.root)
    harness_files = ('tool/benchmarks/benchmark_streaming_tuning.dart', 'tool/benchmarks/odbc_benchmark_fixture.dart')
    harness_identity = file_set_identity(args.root, harness_files)
    summary = {'machine': collect_machine_metadata(), 'source': identity,
               'native': native_identity(library, revision), 'harness_sha256': harness_identity, 'drivers': {}}
    with MeasurementGuard() as guard:
        for driver, keys in {'sql_server': ('ODBC_TEST_DSN_SQL_SERVER', 'ODBC_DSN_SQL_SERVER'),
                             'sql_anywhere': ('ODBC_TEST_DSN', 'ODBC_DSN')}.items():
            dsn = next((os.environ[k] for k in keys if os.environ.get(k)), None)
            if not dsn:
                summary['drivers'][driver] = {'status': 'pending', 'reason': 'DSN unavailable'}
                continue
            reports = []
            env = {**os.environ, 'ODBC_TEST_DSN': dsn, 'ODBC_FAST_NATIVE_LIBRARY': str(library)}
            def measure(count, fetch, buffer, suffix=''):
                name = f'{driver}-{count}-{fetch}-{buffer}{suffix}'
                print(name, flush=True)
                result = subprocess.run(resolve_command(['dart', 'run', 'tool/benchmarks/benchmark_streaming_tuning.dart',
                    str(count), str(fetch), str(buffer)]), cwd=args.root, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace')
                (args.output_dir / (name + '.log')).write_text(result.stdout + result.stderr, encoding='utf-8')
                if result.returncode:
                    raise RuntimeError('Tuning failed: ' + name)
                report = json.loads(next(line for line in reversed(result.stdout.splitlines()) if line.startswith('{')))
                (args.output_dir / (name + '.json')).write_text(json.dumps(report, indent=2), encoding='utf-8')
                return report
            configurations = [(1000, 1048576)] + [(f, b) for f in (1000, 2000, 4000, 8000)
                for b in (65536, 262144, 1048576) if (f, b) != (1000, 1048576)]
            for count in (1000, 8000, 50000):
                for fetch, buffer in configurations:
                    reports.append(measure(count, fetch, buffer))
            selection = select_configuration(reports)
            controls = [measure(count, 1000, 1048576, '-control') for count in (1000, 8000, 50000)]
            baselines = [r for r in reports if (r['fetch_size'], r['buffer_bytes']) == (1000, 1048576)]
            stable = all(control_stable(a, b) for a, b in zip(baselines, controls))
            if not stable:
                selection.update(recommendation=None)
            elif selection['recommendation']:
                choice = selection['recommendation']
                confirmed = [measure(count, choice['fetch_size'], choice['buffer_bytes'], '-confirm') for count in (1000, 8000, 50000)]
                if not select_configuration(controls + confirmed)['recommendation']:
                    selection.update(recommendation=None)
            summary['drivers'][driver] = {'status': 'measured' if stable else 'inconclusive',
                'control_stable': stable, **selection}
            (args.output_dir / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
        summary['interrupted'] = guard.interrupted
        if (guard.interrupted or identity != collect_source_identity(args.root)
                or summary['native'] != native_identity(library, revision)
                or harness_identity != file_set_identity(args.root, harness_files)):
            for value in summary['drivers'].values():
                value.update(status='inconclusive', recommendation=None)
    (args.output_dir / 'summary.json').write_text(json.dumps(summary, indent=2), encoding='utf-8')
    return 2 if any(v['status'] in ('pending', 'inconclusive') for v in summary['drivers'].values()) else 0


if __name__ == '__main__':
    raise SystemExit(main())
