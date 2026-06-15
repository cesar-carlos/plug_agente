from __future__ import annotations

import os
import re
import sys
from dataclasses import dataclass

_ASYNC_SCENARIO_RE = re.compile(
    r"^(?P<label>.+?): (?P<ms>[0-9.]+) ms,.*?encoding=(?P<encoding>[A-Za-z]+),"
    r".*?fallbacks=(?P<fallbacks>\d+)",
    re.MULTILINE,
)

_STREAM_ROWS_PER_SEC_RE = re.compile(
    r"(?P<label>streamQueryBatched|streamQuery)\s*:.*?rowsPerSecond=(?P<rows_per_sec>[0-9.]+)",
    re.MULTILINE | re.IGNORECASE,
)

_STREAM_ROWS_FALLBACK_RE = re.compile(
    r"(?P<label>streamQueryBatched|streamQuery)\s*:\s*(?P<ms>\d+)\s*ms,\s*rows=(?P<rows>\d+)",
    re.MULTILINE | re.IGNORECASE,
)


@dataclass(frozen=True)
class AsyncBenchmarkScenario:
    label: str
    duration_ms: float
    encoding: str
    fallbacks: int


@dataclass(frozen=True)
class StreamingBenchmarkScenario:
    label: str
    rows_per_second: float


def parse_async_benchmark_scenarios(output: str) -> list[AsyncBenchmarkScenario]:
    scenarios: list[AsyncBenchmarkScenario] = []
    for match in _ASYNC_SCENARIO_RE.finditer(output):
        scenarios.append(
            AsyncBenchmarkScenario(
                label=match.group("label").strip(),
                duration_ms=float(match.group("ms")),
                encoding=match.group("encoding"),
                fallbacks=int(match.group("fallbacks")),
            )
        )
    return scenarios


def _rows_per_second_from_match(label: str, rows: int, elapsed_ms: int) -> float:
    if elapsed_ms <= 0:
        return 0.0
    return rows / (elapsed_ms / 1000.0)


def parse_streaming_benchmark_scenarios(output: str) -> list[StreamingBenchmarkScenario]:
    scenarios: list[StreamingBenchmarkScenario] = []
    by_label: dict[str, StreamingBenchmarkScenario] = {}

    for match in _STREAM_ROWS_PER_SEC_RE.finditer(output):
        by_label[match.group("label")] = StreamingBenchmarkScenario(
            label=match.group("label"),
            rows_per_second=float(match.group("rows_per_sec")),
        )

    for match in _STREAM_ROWS_FALLBACK_RE.finditer(output):
        label = match.group("label")
        if label in by_label:
            continue
        rows = int(match.group("rows"))
        elapsed_ms = int(match.group("ms"))
        by_label[label] = StreamingBenchmarkScenario(
            label=label,
            rows_per_second=_rows_per_second_from_match(label, rows, elapsed_ms),
        )

    scenarios.extend(by_label.values())
    return scenarios


def _benchmark_gates_enabled() -> bool:
    return os.environ.get("BENCHMARK_ENFORCE_ODBC_GATES", "").strip().lower() in {
        "1",
        "true",
        "yes",
    }


def _read_positive_float_env(name: str, *, default: float | None = None) -> float | None:
    raw = os.environ.get(name, "").strip()
    if not raw:
        return default
    try:
        value = float(raw)
    except ValueError:
        print(f"Invalid {name}: {raw}", file=sys.stderr)
        raise SystemExit(2)
    if value <= 0:
        print(f"{name} must be > 0 (got {value})", file=sys.stderr)
        raise SystemExit(2)
    return value


def _find_async_scenario(
    scenarios: list[AsyncBenchmarkScenario],
    *,
    label: str,
    encoding: str,
) -> AsyncBenchmarkScenario | None:
    for scenario in scenarios:
        if scenario.label == label and scenario.encoding == encoding:
            return scenario
    return None


def _columnar_speedup(row_major_ms: float, encoding_ms: float) -> float:
    if encoding_ms <= 0:
        return 0.0
    return row_major_ms / encoding_ms


def enforce_async_benchmark_gates(output: str) -> int:
    scenarios = parse_async_benchmark_scenarios(output)
    gates_enabled = _benchmark_gates_enabled()

    if not scenarios:
        if gates_enabled:
            print(
                "Async benchmark gate failed: no recognizable scenario lines in output.",
                file=sys.stderr,
            )
            return 3
        return 0

    max_fallbacks = 0
    if gates_enabled or os.environ.get("BENCHMARK_ODBC_FALLBACKS_MAX", "").strip() != "":
        max_fallbacks = int(_read_positive_float_env("BENCHMARK_ODBC_FALLBACKS_MAX", default=0.0) or 0.0)

    total_fallbacks = sum(scenario.fallbacks for scenario in scenarios)
    if total_fallbacks > max_fallbacks:
        offenders = [scenario for scenario in scenarios if scenario.fallbacks > max_fallbacks]
        details = ", ".join(f"{item.label}={item.fallbacks}" for item in offenders)
        print(
            f"Async benchmark gate failed: fallbacks must be <= {max_fallbacks} "
            f"(observed {total_fallbacks}: {details}).",
            file=sys.stderr,
        )
        return 3

    default_min_speedup = 1.30 if gates_enabled else None
    min_speedup = _read_positive_float_env("BENCHMARK_COLUMNAR_MIN_SPEEDUP", default=default_min_speedup)
    if min_speedup is None:
        return 0

    row_major = _find_async_scenario(scenarios, label="workerCount=4", encoding="rowMajor")
    columnar = _find_async_scenario(scenarios, label="workerCount=4 columnar", encoding="columnar")
    columnar_compressed = _find_async_scenario(
        scenarios,
        label="workerCount=4 columnar compressed",
        encoding="columnarCompressed",
    )
    if row_major is None:
        message = "Columnar speedup gate failed: missing workerCount=4 rowMajor scenario."
        if gates_enabled:
            print(message, file=sys.stderr)
            return 3
        print(f"{message} Skipping.", file=sys.stderr)
        return 0

    speedups: list[tuple[str, float, float]] = []
    if columnar is not None:
        speedups.append(
            (
                "columnar",
                columnar.duration_ms,
                _columnar_speedup(row_major.duration_ms, columnar.duration_ms),
            )
        )
    if columnar_compressed is not None:
        speedups.append(
            (
                "columnarCompressed",
                columnar_compressed.duration_ms,
                _columnar_speedup(row_major.duration_ms, columnar_compressed.duration_ms),
            )
        )

    if not speedups:
        message = (
            "Columnar speedup gate failed: missing workerCount=4 columnar/columnarCompressed scenarios."
        )
        if gates_enabled:
            print(message, file=sys.stderr)
            return 3
        print(f"{message} Skipping.", file=sys.stderr)
        return 0

    best_label, best_ms, best_speedup = max(speedups, key=lambda item: item[2])
    if best_speedup < min_speedup:
        details = ", ".join(
            f"{label}={speedup:.3f} ({duration_ms}ms)"
            for label, duration_ms, speedup in speedups
        )
        print(
            "Columnar speedup gate failed: "
            f"best {best_label} {best_speedup:.3f} < {min_speedup} "
            f"(rowMajor={row_major.duration_ms}ms; {details}).",
            file=sys.stderr,
        )
        return 3

    if len(speedups) > 1:
        details = ", ".join(
            f"{label}={speedup:.3f}"
            for label, _, speedup in speedups
        )
        print(
            f"Columnar speedup gate passed via {best_label}: {best_speedup:.3f} >= {min_speedup} "
            f"({details}; rowMajor={row_major.duration_ms}ms).",
            file=sys.stderr,
        )

    return 0


def enforce_streaming_benchmark_gates(output: str) -> int:
    scenarios = parse_streaming_benchmark_scenarios(output)
    by_label = {scenario.label: scenario for scenario in scenarios}

    gates_enabled = _benchmark_gates_enabled()
    default_min_speedup = 2.0 if gates_enabled else None
    min_speedup = _read_positive_float_env("BENCHMARK_STREAMING_MIN_SPEEDUP", default=default_min_speedup)
    if min_speedup is None:
        return 0

    stream = by_label.get("streamQuery")
    batched = by_label.get("streamQueryBatched")
    if stream is None or batched is None:
        message = "Streaming speedup gate failed: missing streamQuery or streamQueryBatched rows/s."
        if gates_enabled:
            print(message, file=sys.stderr)
            return 3
        print(f"{message} Skipping.", file=sys.stderr)
        return 0

    if stream.rows_per_second <= 0:
        print(
            "Streaming speedup gate failed: streamQuery rows/s must be > 0.",
            file=sys.stderr,
        )
        return 3

    speedup = batched.rows_per_second / stream.rows_per_second
    if speedup < min_speedup:
        print(
            "Streaming speedup gate failed: "
            f"batched/streamQuery {speedup:.3f} < {min_speedup} "
            f"(streamQuery={stream.rows_per_second:.0f} rows/s "
            f"streamQueryBatched={batched.rows_per_second:.0f} rows/s).",
            file=sys.stderr,
        )
        return 3

    return 0
