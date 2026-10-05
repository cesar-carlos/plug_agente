"""Qualify transport with an A/A control and serial A/B, B/A measurements."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.benchmarks.compare_transport_repetitions import compare
from tool.py.script_utils import resolve_command
from tool.py.benchmark_common import collect_source_identity, collect_dependency_provenance, collect_machine_metadata
from tool.benchmarks.measurement_guard import MeasurementGuard, native_identity, validate_dependency_change, file_set_identity

HARNESS_FILES = (
    "tool/benchmarks/benchmark_transport_pipeline.dart",
    "tool/benchmarks/benchmark_transport_pipeline_async_impl.dart",
    "tool/benchmarks/benchmark_transport_pipeline_async_stub.dart",
    "tool/benchmarks/benchmark_vm_diagnostics.dart",
    "test/infrastructure/codecs/transport_repeated_benchmark_test.dart",
    "test/infrastructure/codecs/transport_diagnostics_benchmark_test.dart",
)


def run_measurement(root: Path, output: Path, name: str, *, diagnostics: bool = False, native_library: Path | None = None, legacy: bool = False) -> dict:
    target = output / f"{name}.json"
    environment = os.environ.copy()
    if native_library:
        environment['ODBC_FAST_NATIVE_LIBRARY'] = str(native_library.resolve())
        if legacy:
            destination = root / 'native/target/release' / native_library.name
            destination.parent.mkdir(parents=True, exist_ok=True)
            if native_library.resolve() != destination.resolve():
                shutil.copy2(native_library, destination)
            hook_artifact = root / 'build/odbc-native/pinned' / native_library.name
            hook_artifact.parent.mkdir(parents=True, exist_ok=True)
            if native_library.resolve() != hook_artifact.resolve():
                shutil.copy2(native_library, hook_artifact)
            environment['ODBC_FAST_PREFER_LOCAL_BUILD'] = 'true'
    key = "AGENT_TRANSPORT_DIAGNOSTICS_OUTPUT" if diagnostics else "AGENT_TRANSPORT_BENCH_OUTPUT"
    environment[key] = str(target)
    file = "transport_diagnostics_benchmark_test.dart" if diagnostics else "transport_repeated_benchmark_test.dart"
    command = ["flutter", "test", f"test/infrastructure/codecs/{file}"]
    if diagnostics:
        command.append("--enable-vmservice")
    print(f"Measuring {name}", flush=True)
    with (output / f"{name}.log").open("w", encoding="utf-8") as log:
        result = subprocess.run(resolve_command(command), cwd=root, env=environment, stdout=log, stderr=subprocess.STDOUT)
    if result.returncode != 0 or not target.is_file():
        raise ValueError(f"{name} failed; see {name}.log")
    return json.loads(target.read_text(encoding="utf-8"))


def qualify(control: dict, forward: dict, reverse: dict) -> dict:
    if control["failures"] or control["pending_metrics"]:
        return {"status": "inconclusive", "reason": "Identical-code control violated limits or has missing measurements", "control": control, "forward": forward, "reverse": reverse}
    status = "inconclusive" if forward["pending_metrics"] or reverse["pending_metrics"] else (
        "fail" if forward["failures"] or reverse["failures"] else "pass"
    )
    return {"status": status, "control": control, "forward": forward, "reverse": reverse}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base-dir", type=Path, required=True, help="Isolated checkout; its benchmark harness is replaced")
    parser.add_argument('--base-revision', help='Verified Git reference for an archive without .git')
    parser.add_argument("--candidate-dir", type=Path, default=Path(__file__).resolve().parents[2])
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument('--allow-odbc-change', action='store_true')
    parser.add_argument('--base-native-library', type=Path)
    parser.add_argument('--candidate-native-library', type=Path)
    parser.add_argument('--base-odbc-revision')
    parser.add_argument('--candidate-odbc-revision')
    args = parser.parse_args(argv)
    native_arguments = (args.base_native_library, args.candidate_native_library,
                        args.base_odbc_revision, args.candidate_odbc_revision)
    if args.allow_odbc_change and not all(native_arguments):
        parser.error('ODBC changes require both native binaries and full source revisions')
    if any(native_arguments) and not all(native_arguments):
        parser.error('Provide complete native provenance for both revisions')
    base, candidate, output = args.base_dir.resolve(), args.candidate_dir.resolve(), args.output_dir.resolve()
    if base == candidate:
        parser.error("An isolated comparison checkout is required")
    output.mkdir(parents=True, exist_ok=True)
    harness_identity = file_set_identity(candidate, HARNESS_FILES)
    (output / 'comparison.json').write_text(json.dumps({'status': 'inconclusive', 'reason': 'Measurement in progress'}), encoding='utf-8')
    for name in HARNESS_FILES:
        destination = base / name
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(candidate / name, destination)
    control_checkout = tempfile.TemporaryDirectory(prefix='plug-benchmark-control-', ignore_cleanup_errors=True)
    guard = MeasurementGuard()
    try:
        guard.__enter__()
        revision = None
        if args.base_revision:
            revision = subprocess.run(['git', 'rev-parse', f'{args.base_revision}^{{commit}}'], cwd=candidate, text=True, capture_output=True, check=True).stdout.strip()
            tree = subprocess.run(['git', 'ls-tree', '-r', revision, 'lib'], cwd=candidate, text=True, capture_output=True, check=True).stdout
            import hashlib
            for line in tree.splitlines():
                description, filename = line.split('\t', 1)
                content = (base / filename).read_bytes()
                actual = hashlib.sha1(f'blob {len(content)}\0'.encode() + content).hexdigest()
                if actual != description.split()[2]:
                    raise ValueError(f'Archive source differs from reference: {filename}')
        subprocess.run(resolve_command(["flutter", "pub", "get"]), cwd=base, check=True, stdout=subprocess.DEVNULL)
        dependencies = {'base': collect_dependency_provenance(base), 'candidate': collect_dependency_provenance(candidate)}
        validate_dependency_change(dependencies['base'], dependencies['candidate'], allow_odbc=args.allow_odbc_change)
        native = {} if not all(native_arguments) else {
            'base': native_identity(args.base_native_library, args.base_odbc_revision),
            'candidate': native_identity(args.candidate_native_library, args.candidate_odbc_revision),
        }
        identities = {'base': collect_source_identity(base, revision=revision), 'candidate': collect_source_identity(candidate)}
        control = Path(control_checkout.name) / 'source'
        shutil.copytree(base, control, ignore=shutil.ignore_patterns('.git', '.dart_tool', 'build', '.env', 'artifacts', 'node_modules', 'ephemeral', '.plugin_symlinks', 'target'))
        subprocess.run(resolve_command(['flutter', 'pub', 'get']), cwd=control, check=True, stdout=subprocess.DEVNULL)
        if collect_source_identity(control, revision=identities['base']['commit_sha']) != identities['base']:
            raise ValueError('Identical-code control copy differs from base sources')
        measurements = {}
        for name, root in (
            ("control-1", base), ("control-2", control),
            ("base-forward", base), ("candidate-forward", candidate),
            ("candidate-reverse", candidate), ("base-reverse", base),
        ):
            measurements[name] = run_measurement(root, output, name, native_library=args.candidate_native_library if name.startswith('candidate') else args.base_native_library, legacy=not name.startswith('candidate'))
        control_heap_1 = run_measurement(base, output, "control-1-diagnostics", diagnostics=True, native_library=args.base_native_library, legacy=True)
        control_heap_2 = run_measurement(control, output, "control-2-diagnostics", diagnostics=True, native_library=args.base_native_library, legacy=True)
        base_heap = run_measurement(base, output, "base-diagnostics", diagnostics=True, native_library=args.base_native_library, legacy=True)
        candidate_heap = run_measurement(candidate, output, "candidate-diagnostics", diagnostics=True, native_library=args.candidate_native_library)
        if any(diagnostics.get('diagnostics_version') != 2 for diagnostics in
               (control_heap_1, control_heap_2, base_heap, candidate_heap)):
            raise ValueError('Heap qualification requires diagnostics v2 without retained allocation profiles')
        for name, measurement in measurements.items():
            diagnostics = {"control-1": control_heap_1, "control-2": control_heap_2}.get(name, candidate_heap if name.startswith("candidate") else base_heap)
            measurement["heap_growth_bytes"] = diagnostics["heap_growth_bytes"]
            (output / f"{name}.json").write_text(json.dumps(measurement, indent=2), encoding="utf-8")
        report = qualify(
            compare(measurements["control-1"], measurements["control-2"]),
            compare(measurements["base-forward"], measurements["candidate-forward"]),
            compare(measurements["base-reverse"], measurements["candidate-reverse"]),
        )
        control_reverse = compare(measurements["control-2"], measurements["control-1"])
        report['control_reverse'] = control_reverse
        if control_reverse['failures'] or control_reverse['pending_metrics']:
            report.update(status='inconclusive', reason='Identical-code reverse control is unstable or incomplete')
        report.update(identities)
        report.update(dependencies=dependencies, native=native, machine=collect_machine_metadata(),
                      largest_heartbeat_gap_seconds=guard.largest_gap_seconds,
                      heap_diagnostics_version=2, harness_sha256=harness_identity)
        if guard.interrupted:
            report.update(status='inconclusive', reason='Measurement crossed a suspension or heartbeat interruption')
        if native and (native['base'] != native_identity(args.base_native_library, args.base_odbc_revision)
                       or native['candidate'] != native_identity(args.candidate_native_library, args.candidate_odbc_revision)):
            report.update(status='inconclusive', reason='Native binaries changed during measurement')
        if identities['base'] != collect_source_identity(base, revision=revision) or identities['candidate'] != collect_source_identity(candidate):
            report.update(status='inconclusive', reason='Application sources changed during measurement')
        if any(file_set_identity(root, HARNESS_FILES) != harness_identity for root in (base, candidate, control)):
            report.update(status='inconclusive', reason='Measurement harness changed during measurement')
    except (ValueError, OSError, subprocess.SubprocessError, KeyError, TypeError) as error:
        report = {"status": "inconclusive", "reason": str(error)}
    finally:
        guard.__exit__(None, None, None)
        control_checkout.cleanup()
    (output / "comparison.json").write_text(json.dumps(report, indent=2), encoding="utf-8")
    print(f"Transport qualification: {report['status']}", flush=True)
    return {"pass": 0, "fail": 1, "inconclusive": 2}[report["status"]]


if __name__ == "__main__":
    raise SystemExit(main())
