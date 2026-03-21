import 'package:flutter_test/flutter_test.dart';

/// Keys match `cases` in `odbc_rpc_benchmark_live_e2e_test` JSONL records.
typedef E2eBenchmarkCaseThresholds = Map<String, int>;

/// Compares recorded `cases` to optional max latency (ms) per case key.
///
/// Uses `median_ms` when present, else `elapsed_ms` (single-shot cases).
void assertE2eBenchmarkWithinThresholds({
  required Map<String, dynamic> cases,
  required E2eBenchmarkCaseThresholds thresholds,
}) {
  for (final e in thresholds.entries) {
    final caseKey = e.key;
    final maxMs = e.value;
    final Object? raw = cases[caseKey];
    if (raw is! Map) {
      continue;
    }
    final m = Map<String, dynamic>.from(raw);
    final Object? median = m['median_ms'];
    final Object? elapsed = m['elapsed_ms'];
    final observed = median is num
        ? median.round()
        : elapsed is int
        ? elapsed
        : elapsed is num
        ? elapsed.round()
        : null;
    if (observed == null) {
      continue;
    }
    expect(
      observed,
      lessThanOrEqualTo(maxMs),
      reason:
          '$caseKey: ${observed}ms exceeds ODBC_E2E_BENCHMARK_MAX_MS_* '
          'threshold ${maxMs}ms',
    );
  }
}
