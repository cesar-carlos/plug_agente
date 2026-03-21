import 'package:flutter_test/flutter_test.dart';

import 'e2e_env.dart';

void main() {
  setUp(E2EEnv.resetForTesting);

  tearDown(E2EEnv.resetForTesting);

  group('benchmark env getters', () {
    test('odbcE2eBenchmarkEnabled is true when ODBC_E2E_BENCHMARK=true', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK': 'true',
      });
      expect(E2EEnv.odbcE2eBenchmarkEnabled, isTrue);
    });

    test('odbcE2eBenchmarkRecordEnabled reads ODBC_E2E_BENCHMARK_RECORD', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_RECORD': 'true',
      });
      expect(E2EEnv.odbcE2eBenchmarkRecordEnabled, isTrue);
    });

    test('odbcE2eBenchmarkRecordFile uses custom ODBC_E2E_BENCHMARK_FILE', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_FILE': 'custom/out.jsonl',
      });
      expect(E2EEnv.odbcE2eBenchmarkRecordFile, 'custom/out.jsonl');
    });

    test('odbcE2eBenchmarkDbHosting accepts local and remote', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_DB_HOSTING': 'Local',
      });
      expect(E2EEnv.odbcE2eBenchmarkDbHosting, 'local');

      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_DB_HOSTING': 'REMOTE',
      });
      expect(E2EEnv.odbcE2eBenchmarkDbHosting, 'remote');
    });

    test('odbcE2eBenchmarkDbHosting returns null for invalid value', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_DB_HOSTING': 'cloud',
      });
      expect(E2EEnv.odbcE2eBenchmarkDbHosting, isNull);
    });

    test('odbcE2eBenchmarkMaxMsByCase parses known suffixes', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_MAX_MS_MATERIALIZED': '800',
        'ODBC_E2E_BENCHMARK_MAX_MS_STREAMING': '1200',
        'ODBC_E2E_BENCHMARK_MAX_MS_BAD': 'not-int',
        'ODBC_E2E_BENCHMARK_MAX_MS_BATCH_READS': '0',
      });
      final m = E2EEnv.odbcE2eBenchmarkMaxMsByCase;
      expect(m['rpc_sql_execute_materialized'], 800);
      expect(m['rpc_sql_execute_streaming'], 1200);
      expect(m.containsKey('rpc_sql_execute_batch_reads'), isFalse);
    });
  });
}
