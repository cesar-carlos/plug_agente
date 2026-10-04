"""Compare identical nine-repeat codec harnesses without weakening SLOs."""

import argparse
import json
import math
import statistics
from pathlib import Path


def compare(base, candidate):
    for name in ("harness_version", "dart_version", "platform", "config"):
        if base[name] != candidate[name]:
            raise ValueError(f"Incompatible {name}; measurements cannot be compared")
    if base["config"]["repeats"] != 9:
        raise ValueError("Nine repetitions are required")
    if base["harness_version"] != 2 or base["config"]["iterations"] < 100 or base["config"].get("warmup_iterations", 0) < 10:
        raise ValueError("Qualification requires v2, 100 measurements and ten warmup iterations")

    def profiles(report):
        repetitions = report["repetitions"]
        if len(repetitions) != 9 or len(report["elapsed_us"]) != 9:
            raise ValueError("Incomplete repetitions")
        result = {}
        expected = None
        for rows in repetitions:
            required = {(case, mode, signed) for case in ('small_sql_repetitive', 'large_sql_low_compressibility', 'large_incompressible_blob') for mode in ('none', 'auto', 'gzip') for signed in (False, True)}
            keys = [(row["case"], row["requested_compression"], row["signed"]) for row in rows]
            if set(keys) != required:
                raise ValueError("Incomplete transport scenario set")
            if len(set(keys)) != len(keys) or (expected is not None and keys != expected):
                raise ValueError("Scenario order or membership differs between repetitions")
            expected = keys
            for key, row in zip(keys, rows):
                if row['iterations'] != report['config']['iterations'] or row.get('send_sample_count') != row['iterations'] or row.get('receive_sample_count') != row['iterations'] or any(not math.isfinite(row[field]) or row[field] < 0 for field in ('send_p95_us', 'receive_p95_us')):
                    raise ValueError("Invalid timing or sample count")
                if row["summary"]["error_count"]:
                    raise ValueError(f"Codec errors in {key}")
                result.setdefault(key, []).append(row)
        return result

    before, after = profiles(base), profiles(candidate)
    if list(before) != list(after):
        raise ValueError("Scenario sets differ")
    failures, scenarios = [], []
    for key, rows in before.items():
        updated = after[key]
        for field in ("iterations", "original_bytes", "wire_bytes", "effective_compression"):
            if any(row[field] != rows[0][field] for row in rows + updated):
                raise ValueError(f"Different dataset or wire profile for {key}: {field}")
        result = {"case": key[0], "compression": key[1], "signed": key[2]}
        for field in ("send_p95_us", "receive_p95_us"):
            first = statistics.median(row[field] for row in rows)
            current = statistics.median(row[field] for row in updated)
            result[field] = {"base": first, "candidate": current, "limit": first * 1.05}
            if current > first * 1.05:
                failures.append(f"{key} {field}: {current} > {first * 1.05}")
        scenarios.append(result)
    elapsed_base = statistics.median(base["elapsed_us"])
    elapsed_candidate = statistics.median(candidate["elapsed_us"])
    if not math.isfinite(elapsed_base) or not math.isfinite(elapsed_candidate) or elapsed_base <= 0 or elapsed_candidate <= 0:
        raise ValueError("Invalid elapsed time")
    throughput_ratio = elapsed_base / elapsed_candidate
    if throughput_ratio < 0.85:
        failures.append(f"Whole harness throughput ratio {throughput_ratio} < 0.85")
    # RSS is recorded separately: it must not substitute for a Dart heap gate.
    heap_available = "heap_growth_bytes" in base and "heap_growth_bytes" in candidate
    if heap_available and any(not isinstance(report['heap_growth_bytes'], (int, float)) or not math.isfinite(report['heap_growth_bytes']) or report['heap_growth_bytes'] < 0 for report in (base, candidate)):
        raise ValueError('Invalid Dart heap growth')
    if heap_available and candidate["heap_growth_bytes"] > base["heap_growth_bytes"] * 1.1:
        failures.append("Heap growth exceeds 110% of base")
    pending = [] if heap_available else ["Dart heap growth"]
    return {
        "status": "fail" if failures else ("inconclusive" if pending else "pass"),
        "scenarios": scenarios,
        "throughput_ratio": throughput_ratio,
        "rss_peak_bytes": {"base": base["rss_peak_bytes"], "candidate": candidate["rss_peak_bytes"]},
        "heap_gate_evaluated": heap_available,
        "heap_growth_bytes": {"base": base['heap_growth_bytes'], "candidate": candidate['heap_growth_bytes'], "limit": base['heap_growth_bytes'] * 1.1} if heap_available else None,
        "pending_metrics": pending,
        "failures": failures,
    }


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--base", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    try:
        report = compare(
            json.loads(args.base.read_text(encoding="utf-8")),
            json.loads(args.candidate.read_text(encoding="utf-8")),
        )
    except (ValueError, KeyError, ZeroDivisionError) as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2), encoding="utf-8")
    for failure in report["failures"]:
        print(failure)
    if report["pending_metrics"]:
        print("Not fully validated: " + ", ".join(report["pending_metrics"]))
    return 1 if report["failures"] else (2 if report["pending_metrics"] else 0)


if __name__ == "__main__":
    raise SystemExit(main())
