from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

from tool.py.odbc_benchmark_gate import (
    enforce_async_benchmark_gates,
    enforce_streaming_benchmark_gates,
    parse_async_benchmark_scenarios,
    parse_streaming_benchmark_scenarios,
)


SAMPLE_ASYNC_OUTPUT = """
workerCount=1: 20 ms, workers=1, poolSize=0, maxInFlight=24, encoding=rowMajor, units=24, routed=117, timeouts=0, fallbacks=0
workerCount=4: 10 ms, workers=4, poolSize=0, maxInFlight=24, encoding=rowMajor, units=24, routed=126, timeouts=0, fallbacks=0
workerCount=4 columnar: 18 ms, workers=4, poolSize=0, maxInFlight=24, encoding=columnar, units=24, routed=105, timeouts=0, fallbacks=0
workerCount=4 columnar compressed: 6 ms, workers=4, poolSize=0, maxInFlight=24, encoding=columnarCompressed, units=24, routed=105, timeouts=0, fallbacks=0
"""

SAMPLE_STREAM_OUTPUT = """
streamQuery: 104 ms, rows=1969, chunks=1, rowsPerSecond=18933, fetchSize=0, chunkSize=65536
streamQueryBatched: 45 ms, rows=1969, chunks=2, rowsPerSecond=43756, fetchSize=1000, chunkSize=65536
"""


class OdbcBenchmarkGateTests(unittest.TestCase):
    def test_parse_async_benchmark_scenarios(self) -> None:
        scenarios = parse_async_benchmark_scenarios(SAMPLE_ASYNC_OUTPUT)
        self.assertEqual(len(scenarios), 4)
        self.assertEqual(scenarios[1].encoding, "rowMajor")
        self.assertEqual(scenarios[2].duration_ms, 18.0)
        self.assertEqual(scenarios[3].duration_ms, 6.0)

    def test_parse_streaming_benchmark_scenarios(self) -> None:
        scenarios = parse_streaming_benchmark_scenarios(SAMPLE_STREAM_OUTPUT)
        by_label = {scenario.label: scenario for scenario in scenarios}
        self.assertAlmostEqual(by_label["streamQuery"].rows_per_second, 18933.0)
        self.assertAlmostEqual(by_label["streamQueryBatched"].rows_per_second, 43756.0)

    def test_enforce_async_fallback_gate(self) -> None:
        output = SAMPLE_ASYNC_OUTPUT.replace("fallbacks=0", "fallbacks=1", 1)
        self.assertEqual(enforce_async_benchmark_gates(output), 3)

    def test_enforce_async_columnar_speedup_gate(self) -> None:
        with mock.patch.dict(os.environ, {"BENCHMARK_COLUMNAR_MIN_SPEEDUP": "1.30"}):
            self.assertEqual(enforce_async_benchmark_gates(SAMPLE_ASYNC_OUTPUT), 0)

        slow_all = SAMPLE_ASYNC_OUTPUT.replace(
            "workerCount=4 columnar compressed: 6 ms",
            "workerCount=4 columnar compressed: 18 ms",
        )
        with mock.patch.dict(os.environ, {"BENCHMARK_COLUMNAR_MIN_SPEEDUP": "1.30"}):
            self.assertEqual(enforce_async_benchmark_gates(slow_all), 3)

    def test_enforce_async_columnar_speedup_gate_accepts_columnar_compressed(self) -> None:
        with mock.patch.dict(os.environ, {"BENCHMARK_COLUMNAR_MIN_SPEEDUP": "1.30"}):
            self.assertEqual(enforce_async_benchmark_gates(SAMPLE_ASYNC_OUTPUT), 0)

    def test_parse_streaming_benchmark_scenarios_from_rows_and_elapsed(self) -> None:
        output = """
        streamQuery: 100 ms, rows=1000, chunks=1, fetchSize=0, chunkSize=65536
        streamQueryBatched: 40 ms, rows=1000, chunks=2, fetchSize=1000, chunkSize=65536
        """
        scenarios = parse_streaming_benchmark_scenarios(output)
        by_label = {scenario.label: scenario for scenario in scenarios}
        self.assertAlmostEqual(by_label["streamQuery"].rows_per_second, 10000.0)
        self.assertAlmostEqual(by_label["streamQueryBatched"].rows_per_second, 25000.0)

    def test_enforce_streaming_speedup_gate(self) -> None:
        with mock.patch.dict(os.environ, {"BENCHMARK_STREAMING_MIN_SPEEDUP": "2.0"}):
            self.assertEqual(enforce_streaming_benchmark_gates(SAMPLE_STREAM_OUTPUT), 0)

        slow_batched = SAMPLE_STREAM_OUTPUT.replace("rowsPerSecond=43756", "rowsPerSecond=20000")
        with mock.patch.dict(os.environ, {"BENCHMARK_STREAMING_MIN_SPEEDUP": "2.0"}):
            self.assertEqual(enforce_streaming_benchmark_gates(slow_batched), 3)


if __name__ == "__main__":
    unittest.main()
