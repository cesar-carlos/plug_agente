import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

/// Keys match `cases` in `odbc_rpc_benchmark_live_e2e_test` JSONL records.
typedef E2eBenchmarkCaseThresholds = Map<String, int>;

num? _caseLatencyMs(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final m = Map<String, dynamic>.from(raw);
  final Object? median = m['median_ms'];
  if (median is num) {
    return median;
  }
  final Object? elapsed = m['elapsed_ms'];
  if (elapsed is num) {
    return elapsed;
  }
  return null;
}

bool _mapsMatch(Object? raw, Map<String, dynamic> expected) {
  if (raw is! Map) {
    return false;
  }
  final actual = Map<String, dynamic>.from(raw);
  if (actual.length != expected.length) {
    return false;
  }
  for (final entry in expected.entries) {
    if (actual[entry.key] != entry.value) {
      return false;
    }
  }
  return true;
}

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
    final observed = _caseLatencyMs(raw)?.round();
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

/// Returns prior records with the same target/build/profile/hosting.
List<Map<String, dynamic>> selectComparableE2eBenchmarkRecords({
  required List<Map<String, dynamic>> records,
  required String targetLabel,
  required String buildMode,
  required Map<String, dynamic> benchmarkProfile,
  String? databaseHosting,
}) {
  return records.where((Map<String, dynamic> record) {
    if (record['target_label'] != targetLabel) {
      return false;
    }
    if (record['build_mode'] != buildMode) {
      return false;
    }
    if (!_mapsMatch(record['benchmark_profile'], benchmarkProfile)) {
      return false;
    }
    final hosting = record['database_hosting'];
    if (hosting != databaseHosting) {
      return false;
    }
    return record['cases'] is Map;
  }).toList();
}

/// Fails when current benchmark latency regresses beyond the configured budget.
///
/// The budget is computed from the average comparable baseline latency plus the
/// greater of:
/// - [maxRegressionPercent] of the baseline average
/// - [maxRegressionMs] fixed slack
void assertE2eBenchmarkWithinRegressionBudget({
  required Map<String, dynamic> cases,
  required List<Map<String, dynamic>> baselineRecords,
  required double maxRegressionPercent,
  int maxRegressionMs = 0,
  int window = 5,
}) {
  expect(
    baselineRecords,
    isNotEmpty,
    reason:
        'No comparable benchmark baseline records found for the current '
        'target/profile.',
  );

  final recent = baselineRecords.length > window
      ? baselineRecords.sublist(baselineRecords.length - window)
      : baselineRecords;

  final sums = <String, double>{};
  final counts = <String, int>{};
  for (final record in recent) {
    final rawCases = record['cases'];
    if (rawCases is! Map) {
      continue;
    }
    final baselineCases = Map<String, dynamic>.from(rawCases);
    for (final entry in baselineCases.entries) {
      final latency = _caseLatencyMs(entry.value);
      if (latency == null) {
        continue;
      }
      sums.update(
        entry.key,
        (double current) => current + latency.toDouble(),
        ifAbsent: latency.toDouble,
      );
      counts.update(entry.key, (int current) => current + 1, ifAbsent: () => 1);
    }
  }

  for (final entry in cases.entries) {
    final currentLatency = _caseLatencyMs(entry.value);
    if (currentLatency == null) {
      continue;
    }
    final sampleCount = counts[entry.key];
    if (sampleCount == null || sampleCount <= 0) {
      continue;
    }
    final baselineMean = sums[entry.key]! / sampleCount;
    final regressionBudget = math.max(
      baselineMean * (maxRegressionPercent / 100),
      maxRegressionMs.toDouble(),
    );
    final allowedLatency = baselineMean + regressionBudget;
    expect(
      currentLatency,
      lessThanOrEqualTo(allowedLatency),
      reason:
          '${entry.key}: ${currentLatency.toStringAsFixed(1)}ms exceeds '
          'baseline mean ${baselineMean.toStringAsFixed(1)}ms + '
          'allowed regression ${regressionBudget.toStringAsFixed(1)}ms '
          '($sampleCount sample(s), window=${recent.length})',
    );
  }
}
