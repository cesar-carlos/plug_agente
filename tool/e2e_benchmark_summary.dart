import 'dart:convert';

/// Latency for a benchmark case: prefers `median_ms`, else `elapsed_ms`.
num? e2eBenchmarkLatencyMsFromCase(Object? raw) {
  if (raw is! Map) {
    return null;
  }
  final m = Map<String, dynamic>.from(raw);
  final median = m['median_ms'];
  if (median is num) {
    return median;
  }
  final elapsed = m['elapsed_ms'];
  if (elapsed is num) {
    return elapsed;
  }
  return null;
}

/// Parses non-empty JSON lines into maps (skips invalid lines).
List<Map<String, dynamic>> parseE2eBenchmarkJsonlLines(Iterable<String> lines) {
  final out = <Map<String, dynamic>>[];
  for (final line in lines) {
    if (line.trim().isEmpty) {
      continue;
    }
    try {
      final o = jsonDecode(line);
      if (o is Map<String, dynamic>) {
        out.add(o);
      }
    } on Object {
      // skip bad line
    }
  }
  return out;
}

/// Text lines for CLI / tests (no I/O).
List<String> formatE2eBenchmarkSummary({
  required List<Map<String, dynamic>> records,
  required String filePathLabel,
  required int totalRawLines,
  int window = 10,
}) {
  if (records.isEmpty) {
    return <String>['No valid JSON objects in $filePathLabel'];
  }

  final byTarget = <String, List<Map<String, dynamic>>>{};
  for (final r in records) {
    final label = r['target_label'] as String? ?? 'unknown';
    byTarget.putIfAbsent(label, () => <Map<String, dynamic>>[]).add(r);
  }

  final out = <String>[
    '=== E2E ODBC RPC benchmark summary ===',
    'File: $filePathLabel',
    'Total lines: $totalRawLines',
    '',
  ];

  for (final e in byTarget.entries) {
    final target = e.key;
    final list = e.value;
    out.add('--- target: $target (${list.length} record(s)) ---');
    final last = list.last;
    final cases = last['cases'];
    if (cases is! Map) {
      out.add('  (no cases in last record)\n');
      continue;
    }
    final caseMap = Map<String, dynamic>.from(cases);

    for (final ce in caseMap.entries) {
      final caseKey = ce.key;
      final samples = <num>[];
      for (final r in list) {
        final c = r['cases'];
        if (c is! Map) {
          continue;
        }
        final lat = e2eBenchmarkLatencyMsFromCase(c[caseKey]);
        if (lat != null) {
          samples.add(lat);
        }
      }
      if (samples.isEmpty) {
        continue;
      }
      final recent = samples.length > window
          ? samples.sublist(samples.length - window)
          : samples;
      final avg =
          recent.fold<double>(0, (a, b) => a + b.toDouble()) / recent.length;
      final lastMs = e2eBenchmarkLatencyMsFromCase(ce.value);
      out.add(
        '  $caseKey: last_median_ms=${lastMs?.toStringAsFixed(1) ?? "—"}  '
        'avg_last_${recent.length}_ms=${avg.toStringAsFixed(1)}',
      );
    }
    final runId = last['run_id'];
    final at = last['recorded_at'];
    final mode = last['build_mode'];
    out.add('  [last record run_id=$runId at=$at build_mode=$mode]\n');
  }

  return out;
}
