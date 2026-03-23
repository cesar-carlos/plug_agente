@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_execute_result_payload_builder.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw =
      E2EEnv.get('SQL_EXECUTE_RESULT_PAYLOAD_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _rows() {
  final raw = E2EEnv.get('SQL_EXECUTE_RESULT_PAYLOAD_BENCHMARK_ROWS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 2500;
  }
  return n.clamp(1, 100000);
}

int _resultSets() {
  final raw =
      E2EEnv.get('SQL_EXECUTE_RESULT_PAYLOAD_BENCHMARK_RESULT_SETS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 2) {
    return 3;
  }
  return n.clamp(2, 32);
}

QueryResponse _multiResultResponse(int sets, int rowsPerSet) {
  final resultSets = <QueryResultSet>[];
  final items = <QueryResponseItem>[];
  for (var s = 0; s < sets; s++) {
    final rows = List<Map<String, dynamic>>.generate(
      rowsPerSet,
      (int r) => <String, dynamic>{'s': s, 'r': r},
      growable: false,
    );
    final rs = QueryResultSet(
      index: s,
      rows: rows,
      rowCount: rows.length,
      columnMetadata: [
        <String, dynamic>{'name': 's'},
        <String, dynamic>{'name': 'r'},
      ],
    );
    resultSets.add(rs);
    items.add(
      QueryResponseItem.resultSet(index: s, resultSet: rs),
    );
  }
  return QueryResponse(
    id: 'bench-id',
    requestId: 'req',
    agentId: 'agent',
    data: resultSets.first.rows,
    timestamp: DateTime.utc(2024),
    resultSets: resultSets,
    items: items,
  );
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('SQL_EXECUTE_RESULT_PAYLOAD_BENCHMARK') != 'true') {
    group('SqlExecuteResultPayloadBuilder benchmark', () {
      test(
        'skipped — set SQL_EXECUTE_RESULT_PAYLOAD_BENCHMARK=true to run',
        () {},
        skip:
            'Defina SQL_EXECUTE_RESULT_PAYLOAD_BENCHMARK=true para medir buildExecuteResultData.',
      );
    });
    return;
  }

  group('SqlExecuteResultPayloadBuilder benchmark', () {
    test('should record buildExecuteResultData for multi-result response', () {
      final rowsPerSet = _rows();
      final setCount = _resultSets();
      final iterations = _iterations();
      final response = _multiResultResponse(setCount, rowsPerSet);
      final limited = response.resultSets.first.rows;

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final map = SqlExecuteResultPayloadBuilder.buildExecuteResultData(
            response,
            startedAt: DateTime.utc(2024),
            finishedAt: DateTime.utc(2024).add(const Duration(seconds: 1)),
            limitedRows: limited,
            wasTruncated: false,
            sqlHandlingMode: SqlHandlingMode.managed,
            effectiveMaxRows: 50000,
          );
          expect(map['multi_result'], isTrue);
          expect(map['result_sets'], isA<List<dynamic>>());
          expect((map['result_sets']! as List<dynamic>).length, setCount);
        },
        iterations: iterations,
      );

      if (E2EEnv.get('SQL_EXECUTE_RESULT_PAYLOAD_BENCHMARK_RECORD') == 'true') {
        final custom =
            E2EEnv.get('SQL_EXECUTE_RESULT_PAYLOAD_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}sql_execute_result_payload.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'sql_execute_result_payload_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'result_sets': setCount,
              'rows_per_set': rowsPerSet,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'build_execute_result_data_multi': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
