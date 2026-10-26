"""Run an isolated Windows UI soak and compare explicit version baselines."""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import platform
from pathlib import Path
import shutil
import subprocess
import tempfile
import time

ROOT = Path(__file__).resolve().parents[2]
PHASES = ("idle-visible", "running-visible", "running-tray", "running-restored",
          "running-visible-tickers-off", "finished-visible")
COMPATIBILITY = ("format", "os", "machineId", "sdkRevision", "processors", "mode", "phaseSeconds", "scenario")


def summarize(path: Path) -> dict:
    rows = [json.loads(line) for line in path.read_text(encoding="utf-8-sig").splitlines() if line.strip()]
    if not rows or rows[-1] != {"completed": True}:
        raise ValueError("Incomplete probe; a baseline requires successful cleanup.")
    if any("fatal" in row or "error" in row for row in rows):
        raise ValueError("Probe contains runtime failures.")
    metadata = rows[0].get("metadata", {})
    if any(key not in metadata for key in COMPATIBILITY) or metadata["mode"] != "profile":
        raise ValueError("Missing or incompatible profile metadata.")
    if metadata["processors"] < 1 or metadata["phaseSeconds"] < 30:
        raise ValueError("Invalid measurement configuration.")
    phases = {}
    for phase in PHASES:
        samples = [row for row in rows if row.get("phase") == phase]
        if not samples:
            raise ValueError(f"Missing phase: {phase}")
        expected_seconds = metadata["phaseSeconds"] if phase.startswith("running-") else 30
        if samples[-1]["elapsedMs"] - samples[0]["elapsedMs"] < (expected_seconds - 6) * 1000:
            raise ValueError(f"Shortened phase: {phase}")
        stable = [row for row in samples if row["elapsedMs"] >= samples[0]["elapsedMs"] + 10000]
        if len(stable) < 2:
            raise ValueError(f"Insufficient stable samples: {phase}")
        for row in stable:
            for key in ("elapsedMs", "cpuMicros", "frames", "rssBytes", "commitBytes", "providerNotifications"):
                if not isinstance(row[key], (int, float)) or not math.isfinite(row[key]) or row[key] < 0:
                    raise ValueError(f"Invalid {key}: {phase}")
            if row["processors"] != metadata["processors"]:
                raise ValueError("Processor count changed during measurement.")
            if phase.startswith("running-") and (row["running"] != 1 or len(row["actionJobs"]) != 1):
                raise ValueError(f"Action was not running: {phase}")
            if phase == "running-tray" and row["renderingEnabled"] is not False:
                raise ValueError("Tray phase was not hidden.")
        for before, after in zip(stable, stable[1:]):
            if after["elapsedMs"] <= before["elapsedMs"] or any(
                after[key] < before[key] for key in ("cpuMicros", "frames", "providerNotifications")
            ):
                raise ValueError(f"Measurement counter reset: {phase}")
        first, last = stable[0], stable[-1]
        seconds = (last["elapsedMs"] - first["elapsedMs"]) / 1000
        times = [(r["elapsedMs"] - first["elapsedMs"]) / 60000 for r in stable]
        rss = [r["rssBytes"] / 1048576 for r in stable]
        mean_t, mean_rss = sum(times) / len(times), sum(rss) / len(rss)
        slope = sum((t - mean_t) * (m - mean_rss) for t, m in zip(times, rss)) / sum(
            (t - mean_t) ** 2 for t in times)
        phases[phase] = {
            "seconds": seconds,
            "cpuPercentMachine": (last["cpuMicros"] - first["cpuMicros"]) / seconds / 1e6 / metadata["processors"] * 100,
            "framesPerSecond": (last["frames"] - first["frames"]) / seconds,
            "rssPeakMiB": max(rss),
            "rssGrowthMiBPerMinute": slope,
            "commitPeakMiB": max(r["commitBytes"] for r in stable) / 1048576,
            "providerNotifications": last["providerNotifications"] - first["providerNotifications"],
            "lifecycleTransitions": sum(a.get("lifecycle") != b.get("lifecycle")
                for a, b in zip(stable, stable[1:])),
        }
    return {"metadata": metadata, "phases": phases, "completed": True}


def compare(current: dict, baseline: dict) -> dict:
    if not current.get("completed") or not baseline.get("completed"):
        raise ValueError("Both runs must be complete.")
    for key in COMPATIBILITY:
        if key not in baseline["metadata"] or current["metadata"].get(key) != baseline["metadata"][key]:
            raise ValueError(f"Incompatible baseline: {key}")
    if any(current["metadata"][key] == "unknown" for key in ("machineId", "sdkRevision")):
        raise ValueError("Comparison requires identified machine and Flutter SDK.")
    # Absolute allowances prevent noise near zero from becoming a false regression.
    tolerances = {"cpuPercentMachine": .25, "rssPeakMiB": 32,
                  "commitPeakMiB": 32, "framesPerSecond": 1,
                  "rssGrowthMiBPerMinute": 1}
    differences, regressions, inconclusive = {}, [], []
    for phase in PHASES:
        if any(report["phases"][phase].get("lifecycleTransitions", 0) for report in (current, baseline)):
            inconclusive.append(phase)
        differences[phase] = {}
        for metric, allowance in tolerances.items():
            if metric == "rssGrowthMiBPerMinute" and min(
                baseline["phases"][phase]["seconds"], current["phases"][phase]["seconds"]
            ) < 300:
                differences[phase][metric] = {"status": "insufficient_duration", "minimumSeconds": 300}
                continue
            old, new = baseline["phases"][phase][metric], current["phases"][phase][metric]
            if not math.isfinite(old) or not math.isfinite(new):
                raise ValueError("Nonfinite baseline metric.")
            limit = max(old, 0) * 1.2 + allowance
            differences[phase][metric] = {"baseline": old, "current": new, "limit": limit}
            if new > limit:
                regressions.append(f"{phase}.{metric}")
    return {"differences": differences, "regressions": regressions,
            "inconclusivePhases": inconclusive,
            "interpretation": "Repeat phases with focus changes before attributing differences to code." if inconclusive else "Controlled phase comparison.",
            "baselineVersion": baseline["metadata"]["appVersion"],
            "currentVersion": current["metadata"]["appVersion"]}


def run(args) -> Path:
    if os.name != "nt":
        raise ValueError("The native UI probe requires Windows.")
    if not 30 <= args.phase_seconds <= 900:
        raise ValueError("Phase duration must be 30..900 seconds (450 is about 31 minutes total).")
    output = args.output.resolve()
    output.mkdir(parents=True, exist_ok=False)
    dart = args.flutter_root / "bin/cache/dart-sdk/bin/dart.exe"
    flutter = args.flutter_root / "bin/cache/flutter_tools.snapshot"
    revision = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    dirty = bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT))
    sdk = json.loads(subprocess.check_output([str(dart), str(flutter), "--version", "--machine"], cwd=ROOT, text=True))
    with (output / "build.log").open("w", encoding="utf-8") as log:
        subprocess.run([str(dart), str(flutter), "build", "windows", "--profile", "--no-pub",
                        "-t", "tool/benchmarks/action_ui_resource_probe.dart"], cwd=ROOT,
                       stdout=log, stderr=subprocess.STDOUT, check=True)
    binary = ROOT / "build/windows/x64/runner/Profile/plug_agente.exe"
    fixture = Path(tempfile.mkdtemp(prefix="plug-ui-probe-"))
    environment = {**os.environ, "PLUG_UI_PROBE_ROOT": str(fixture),
                   "PLUG_UI_PROBE_SECONDS": str(args.phase_seconds),
                   "PLUG_UI_PROBE_REVISION": revision, "PLUG_UI_PROBE_DIRTY": str(dirty).lower(),
                   "PLUG_UI_PROBE_MACHINE": hashlib.sha256(platform.node().encode()).hexdigest(),
                   "PLUG_UI_PROBE_SDK": sdk["frameworkRevision"]}
    (output / "run.json").write_text(json.dumps({"sourceRevision": revision, "sourceDirty": dirty,
        "binarySha256": hashlib.sha256(binary.read_bytes()).hexdigest(),
        "appPayloadSha256": hashlib.sha256((binary.parent / "data/app.so").read_bytes()).hexdigest(),
        "fixture": str(fixture)}, indent=2))
    process = None
    deadline = time.monotonic() + args.phase_seconds * 4 + 180
    try:
        with (output / "application.log").open("w", encoding="utf-8") as log:
            # This freshly built private entrypoint uses the native validation lane:
            # no operational singleton handoff or crash restart registration.
            # Dart still performs the full real window/tray bootstrap in private storage.
            process = subprocess.Popen([str(binary), "--installation-check"], cwd=fixture,
                                       env=environment, stdout=log, stderr=log)
            while process.poll() is None:
                if time.monotonic() >= deadline:
                    raise TimeoutError("Probe exceeded its bounded duration.")
                try:
                    process.wait(timeout=30)
                except subprocess.TimeoutExpired:
                    samples = fixture / "samples.jsonl"
                    contents = samples.read_text(encoding="utf-8") if samples.exists() else ""
                    lines = contents.splitlines() if contents.endswith("\n") else contents.splitlines()[:-1]
                    latest = json.loads(lines[-1]) if lines else {}
                    print(f"Probe: {latest.get('phase', 'starting')} ({latest.get('elapsedMs', 0) // 1000}s)", flush=True)
            if process.returncode:
                raise RuntimeError(f"Probe exited with {process.returncode}; inspect application.log.")
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            process.wait(timeout=10)
        samples = fixture / "samples.jsonl"
        if samples.exists():
            shutil.copyfile(samples, output / "samples.jsonl")
        for log in fixture.rglob("plug_agente_errors.log*"):
            destination = output / "runtime-logs" / log.relative_to(fixture)
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(log, destination)
    return output / "samples.jsonl"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    soak = commands.add_parser("run", help="Build and run; default duration is approximately 31 minutes")
    soak.add_argument("--flutter-root", type=Path, required=True)
    soak.add_argument("--phase-seconds", type=int, default=450)
    soak.add_argument("--output", type=Path, required=True, help="New evidence directory; never overwritten")
    report = commands.add_parser("summarize")
    report.add_argument("samples", type=Path)
    report.add_argument("--output", type=Path, required=True)
    for command in (soak, report):
        command.add_argument("--baseline", type=Path, help="Explicit prior summary from compatible machine/configuration")
    args = parser.parse_args()
    try:
        samples = run(args) if args.command == "run" else args.samples
        summary = summarize(samples)
        if args.baseline:
            summary["comparison"] = compare(summary, json.loads(args.baseline.read_text(encoding="utf-8-sig")))
        destination = args.output / "summary.json" if args.command == "run" else args.output
        with destination.open("x", encoding="utf-8") as stream:
            json.dump(summary, stream, indent=2, allow_nan=False)
        print(destination)
        comparison = summary.get("comparison", {})
        return 2 if comparison.get("regressions") or comparison.get("inconclusivePhases") else 0
    except (ValueError, KeyError, OSError, RuntimeError, subprocess.SubprocessError) as error:
        parser.exit(1, f"Probe failed: {error}\n")


if __name__ == "__main__":
    raise SystemExit(main())
