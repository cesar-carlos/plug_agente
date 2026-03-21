// ignore_for_file: avoid_print

/// Reads ODBC RPC benchmark JSONL and prints per-target / per-case summary.
///
/// Usage:
///   dart run tool/summarize_e2e_benchmark.dart
///   dart run tool/summarize_e2e_benchmark.dart path/to/history.jsonl
///
/// Compares the latest run's `median_ms` (or `elapsed_ms`) to the average of
/// the last N runs (N = 10, capped by available records) per `target_label` and
/// case key.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'e2e_benchmark_summary.dart';

String _projectRootPath() {
  final scriptPath = Platform.script.toFilePath();
  final toolDir = File(scriptPath).parent;
  final candidate = toolDir.parent.path;
  if (File(p.join(candidate, 'pubspec.yaml')).existsSync()) {
    return candidate;
  }
  var dir = Directory.current;
  for (var i = 0; i < 16; i++) {
    final pub = p.join(dir.path, 'pubspec.yaml');
    if (File(pub).existsSync()) {
      return dir.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) {
      break;
    }
    dir = parent;
  }
  return Directory.current.path;
}

void main(List<String> args) {
  final root = _projectRootPath();
  final configured = args.isNotEmpty
      ? args.first
      : p.join(root, 'benchmark', 'e2e_odbc_rpc.jsonl');
  final file = p.isAbsolute(configured)
      ? File(configured)
      : File(p.normalize(p.join(root, configured)));

  if (!file.existsSync()) {
    print('File not found: ${file.path}');
    print('Run benchmarks with ODBC_E2E_BENCHMARK_RECORD=true first.');
    exitCode = 1;
    return;
  }

  final lines = file
      .readAsLinesSync()
      .where((l) => l.trim().isNotEmpty)
      .toList();
  if (lines.isEmpty) {
    print('No records in ${file.path}');
    return;
  }

  final records = parseE2eBenchmarkJsonlLines(lines);
  if (records.isEmpty) {
    print('No valid JSON objects in ${file.path}');
    exitCode = 1;
    return;
  }

  final summary = formatE2eBenchmarkSummary(
    records: records,
    filePathLabel: file.path,
    totalRawLines: lines.length,
  );
  summary.forEach(print);
}
