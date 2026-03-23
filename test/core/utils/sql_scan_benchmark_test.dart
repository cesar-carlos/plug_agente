@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/split_sql_statements.dart';
import 'package:plug_agente/core/utils/sql_dangerous_pattern_scan.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('SQL_SCAN_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _literalClauses() {
  final raw = E2EEnv.get('SQL_SCAN_BENCHMARK_LITERAL_CLAUSES')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 4000;
  }
  return n.clamp(1, 200000);
}

String _buildScanSql(int clauses) {
  final b = StringBuffer('SELECT 1 WHERE 1=1');
  for (var i = 0; i < clauses; i++) {
    b.write(" AND 'semi;$i' = 'semi;$i'");
  }
  return b.toString();
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('SQL_SCAN_BENCHMARK') != 'true') {
    group('SQL scan benchmark', () {
      test(
        'skipped — set SQL_SCAN_BENCHMARK=true to run',
        () {},
        skip:
            'Defina SQL_SCAN_BENCHMARK=true no .env para medir split/dangerous scan.',
      );
    });
    return;
  }

  group('SQL scan benchmark', () {
    test('should record splitSqlStatements + multi + dangerous scan', () {
      final clauses = _literalClauses();
      final sql = _buildScanSql(clauses);
      final iterations = _iterations();

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final parts = splitSqlStatements(sql);
          expect(parts, hasLength(1));
          expect(sqlHasMultipleTopLevelStatements(sql), isFalse);
          expect(sqlContainsTopLevelDangerousPatterns(sql), isFalse);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('SQL_SCAN_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('SQL_SCAN_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}sql_scan.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'sql_scan_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'literal_clauses': clauses,
              'sql_chars': sql.length,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'split_and_dangerous_scan': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
