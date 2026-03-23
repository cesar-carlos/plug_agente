@Tags(['benchmark'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_result_mapper.dart';
import 'package:uuid/uuid.dart';

import '../../helpers/e2e_benchmark_recorder.dart';
import '../../helpers/e2e_env.dart';
import '../../helpers/live_test_env.dart';

int _iterations() {
  final raw = E2EEnv.get('ODBC_RESULT_MAP_BENCHMARK_ITERATIONS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 3) {
    return 12;
  }
  return n.clamp(3, 128);
}

int _rows() {
  final raw = E2EEnv.get('ODBC_RESULT_MAP_BENCHMARK_ROWS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 8000;
  }
  return n.clamp(1, 200000);
}

int _cols() {
  final raw = E2EEnv.get('ODBC_RESULT_MAP_BENCHMARK_COLS')?.trim();
  final n = int.tryParse(raw ?? '');
  if (n == null || n < 1) {
    return 12;
  }
  return n.clamp(1, 256);
}

QueryResult _buildResult(int rows, int cols) {
  final columns = List<String>.generate(cols, (int i) => 'c$i');
  final data = List<List<dynamic>>.generate(
    rows,
    (int r) => List<dynamic>.generate(cols, (int c) => r + c),
    growable: false,
  );
  return QueryResult(
    columns: columns,
    rows: data,
    rowCount: rows,
  );
}

void main() {
  setUpAll(() async {
    await loadLiveTestEnv();
  });

  if (E2EEnv.get('ODBC_RESULT_MAP_BENCHMARK') != 'true') {
    group('OdbcGatewayQueryResultMapper benchmark', () {
      test(
        'skipped — set ODBC_RESULT_MAP_BENCHMARK=true to run',
        () {},
        skip:
            'Defina ODBC_RESULT_MAP_BENCHMARK=true no .env para medir convertQueryResultToMaps.',
      );
    });
    return;
  }

  group('OdbcGatewayQueryResultMapper benchmark', () {
    test('should record convertQueryResultToMaps wall time', () {
      final rowCount = _rows();
      final colCount = _cols();
      final iterations = _iterations();
      final result = _buildResult(rowCount, colCount);

      final stats = E2eBenchmarkStats.measureSync(
        () {
          final maps = OdbcGatewayQueryResultMapper.convertQueryResultToMaps(
            result,
          );
          expect(maps, hasLength(rowCount));
          expect(maps.first.length, colCount);
        },
        iterations: iterations,
      );

      // ignore: avoid_print
      print(
        '[benchmark.odbc_result_map] rows=$rowCount cols=$colCount '
        'iterations=$iterations median_ms=${stats.medianMs} '
        'p90_ms=${stats.p90Ms} mean_ms=${stats.meanMs.toStringAsFixed(2)}',
      );

      if (E2EEnv.get('ODBC_RESULT_MAP_BENCHMARK_RECORD') == 'true') {
        final custom = E2EEnv.get('ODBC_RESULT_MAP_BENCHMARK_FILE')?.trim();
        final relative = (custom != null && custom.isNotEmpty)
            ? custom
            : 'benchmark${Platform.pathSeparator}odbc_result_map.jsonl';
        appendE2eBenchmarkRecord(
          file: resolveE2eBenchmarkOutputFile(relative),
          record: <String, dynamic>{
            'schema_version': 1,
            'suite': 'odbc_result_map_benchmark',
            'run_id': const Uuid().v4(),
            'recorded_at': DateTime.now().toUtc().toIso8601String(),
            'benchmark_profile': <String, dynamic>{
              'rows': rowCount,
              'cols': colCount,
              'iterations': iterations,
            },
            'cases': <String, dynamic>{
              'convert_query_result_to_maps': stats.toJson(),
            },
          },
        );
      }
    });
  });
}
