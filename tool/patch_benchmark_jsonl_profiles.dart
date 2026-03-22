// ignore_for_file: avoid_print

/// Merges missing `benchmark_profile` keys so JSONL baselines match current
/// `selectComparableE2eBenchmarkRecords` filters (exact map length/keys).
///
/// Usage:
///   dart run tool/patch_benchmark_jsonl_profiles.dart
///   dart run tool/patch_benchmark_jsonl_profiles.dart benchmark/custom.jsonl
library;

import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final targets = args.isNotEmpty
      ? args
      : <String>[
          'benchmark/e2e_odbc_rpc.jsonl',
          'benchmark/socket_transport.jsonl',
        ];

  for (final rel in targets) {
    final f = File(rel);
    if (!f.existsSync()) {
      stderr.writeln('skip missing $rel');
      continue;
    }
    final out = <String>[];
    for (final line in f.readAsLinesSync()) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) {
        continue;
      }
      final obj = jsonDecode(trimmed) as Map<String, dynamic>;
      final suite = obj['suite'] as String?;
      final rawProfile = obj['benchmark_profile'];
      if (rawProfile is Map) {
        final profile = Map<String, dynamic>.from(rawProfile);
        if (suite == 'odbc_rpc_benchmark') {
          profile.putIfAbsent('batch_command_count', () => 3);
          profile.putIfAbsent('materialized_max_rows', () => 0);
          profile.putIfAbsent('idempotency_waste_bytes', () => 0);
        } else if (suite == 'socket_transport_benchmark') {
          profile.putIfAbsent('include_jumbo_isolate_path', () => false);
          if (profile['include_jumbo_isolate_path'] == true) {
            profile.putIfAbsent('jumbo_blob_bytes', () => 280 * 1024);
          }
        }
        obj['benchmark_profile'] = profile;
      }
      out.add(jsonEncode(obj));
    }
    f.writeAsStringSync('${out.join('\n')}\n');
    print('Patched ${out.length} records in $rel');
  }
}
