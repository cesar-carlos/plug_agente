@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/validation/sql_validator.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('SQL_VALIDATOR_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _spacePad() {
  final raw = E2EEnv.get('SQL_VALIDATOR_BENCHMARK_SPACE_PAD')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 0) {
    return 12000;
  }
  return n.clamp(0, 500000);
}

int _orderTerms() {
  final raw = E2EEnv.get('SQL_VALIDATOR_BENCHMARK_ORDER_TERMS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 200;
  }
  return n.clamp(1, 5000);
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('SQL_VALIDATOR_BENCHMARK') != 'true') {
    group('SqlValidator benchmark', () {
      test(
        'skipped — set SQL_VALIDATOR_BENCHMARK=true to run',
        () {},
        skip:
            'Defina SQL_VALIDATOR_BENCHMARK=true no .env para medir SqlValidator.',
      );
    });
    return;
  }

  group('SqlValidator benchmark', () {
    test('should record validateSqlForExecution on padded SELECT', () {
      final pad = _spacePad();
      final iterations = _iterations();
      final sql = '${' ' * pad}SELECT${' ' * pad}1';

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final r = SqlValidator.validateSqlForExecution(sql);
          expect(r.isSuccess(), isTrue);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('SQL_VALIDATOR_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('SQL_VALIDATOR_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}sql_validator.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'sql_validator_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'space_pad_each_side': pad,
              'iterations': iterations,
              'case': 'validate_sql_for_execution',
            },
            'cases': <String, dynamic>{
              'validate_sql_for_execution': stats.toJson(),
            },
          },
        );
      }
    });

    test('should record validatePaginationQuery with many ORDER BY terms', () {
      final terms = _orderTerms();
      final iterations = _iterations();
      final orderList = List.filled(terms, 'id ASC').join(', ');
      final sql = 'SELECT id FROM dbo.t ORDER BY $orderList';

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final r = SqlValidator.validatePaginationQuery(sql);
          expect(r.isSuccess(), isTrue);
          expect(r.getOrNull()!.orderBy.length, terms);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('SQL_VALIDATOR_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('SQL_VALIDATOR_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}sql_validator.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'sql_validator_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'order_by_terms': terms,
              'sql_chars': sql.length,
              'iterations': iterations,
              'case': 'validate_pagination_query',
            },
            'cases': <String, dynamic>{
              'validate_pagination_query': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
