import 'package:flutter_test/flutter_test.dart';

import '../../tool/e2e_benchmark_profile_parse.dart';
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

    test('benchmark pool settings parse valid values', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_POOL_MODE': 'native',
        'ODBC_E2E_BENCHMARK_POOL_SIZE': '8',
        'ODBC_E2E_BENCHMARK_CONCURRENCY': '6',
        'ODBC_E2E_BENCHMARK_SEED_ROWS': '96',
        'ODBC_E2E_BENCHMARK_MAX_RESULT_BUFFER_MB': '64',
        'ODBC_E2E_BENCHMARK_STREAMING_CHUNK_SIZE_KB': '2048',
        'ODBC_E2E_BENCHMARK_LOGIN_TIMEOUT_SECONDS': '12',
      });

      expect(E2EEnv.odbcE2eBenchmarkPoolMode, 'native');
      expect(E2EEnv.odbcE2eBenchmarkPoolSize, 8);
      expect(E2EEnv.odbcE2eBenchmarkConcurrency, 6);
      expect(E2EEnv.odbcE2eBenchmarkSeedRows, 96);
      expect(E2EEnv.odbcE2eBenchmarkMaxResultBufferMb, 64);
      expect(E2EEnv.odbcE2eBenchmarkStreamingChunkSizeKb, 2048);
      expect(E2EEnv.odbcE2eBenchmarkLoginTimeoutSeconds, 12);
    });

    test('benchmark pool settings fall back to defaults on invalid values', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_POOL_MODE': 'broken',
        'ODBC_E2E_BENCHMARK_POOL_SIZE': '0',
        'ODBC_E2E_BENCHMARK_CONCURRENCY': '-1',
        'ODBC_E2E_BENCHMARK_SEED_ROWS': 'x',
        'ODBC_E2E_BENCHMARK_MAX_RESULT_BUFFER_MB': '',
        'ODBC_E2E_BENCHMARK_STREAMING_CHUNK_SIZE_KB': '0',
        'ODBC_E2E_BENCHMARK_LOGIN_TIMEOUT_SECONDS': '-5',
      });

      expect(E2EEnv.odbcE2eBenchmarkPoolMode, 'lease');
      expect(E2EEnv.odbcE2eBenchmarkPoolSize, 4);
      expect(E2EEnv.odbcE2eBenchmarkConcurrency, 1);
      expect(E2EEnv.odbcE2eBenchmarkSeedRows, 32);
      expect(E2EEnv.odbcE2eBenchmarkMaxResultBufferMb, 32);
      expect(E2EEnv.odbcE2eBenchmarkStreamingChunkSizeKb, 1024);
      expect(E2EEnv.odbcE2eBenchmarkLoginTimeoutSeconds, 30);
    });

    test('baseline regression settings parse valid values', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_BASELINE_FILE': 'benchmark/baseline.jsonl',
        'ODBC_E2E_BENCHMARK_MAX_REGRESSION_PERCENT': '12.5',
        'ODBC_E2E_BENCHMARK_MAX_REGRESSION_MS': '15',
        'ODBC_E2E_BENCHMARK_BASELINE_WINDOW': '7',
      });

      expect(
        E2EEnv.odbcE2eBenchmarkBaselineFile,
        'benchmark/baseline.jsonl',
      );
      expect(E2EEnv.odbcE2eBenchmarkMaxRegressionPercent, 12.5);
      expect(E2EEnv.odbcE2eBenchmarkMaxRegressionMs, 15);
      expect(E2EEnv.odbcE2eBenchmarkBaselineWindow, 7);
    });

    test('baseline regression settings fall back on invalid values', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_BASELINE_FILE': '',
        'ODBC_E2E_BENCHMARK_MAX_REGRESSION_PERCENT': '-1',
        'ODBC_E2E_BENCHMARK_MAX_REGRESSION_MS': '-5',
        'ODBC_E2E_BENCHMARK_BASELINE_WINDOW': '0',
      });

      expect(E2EEnv.odbcE2eBenchmarkBaselineFile, isNull);
      expect(E2EEnv.odbcE2eBenchmarkMaxRegressionPercent, isNull);
      expect(E2EEnv.odbcE2eBenchmarkMaxRegressionMs, 0);
      expect(E2EEnv.odbcE2eBenchmarkBaselineWindow, 5);
    });

    test('timeout cancel requirement flag reads boolean env', () {
      expect(E2EEnv.odbcE2eBenchmarkRequireTimeoutCancel, isFalse);

      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_REQUIRE_TIMEOUT_CANCEL': 'true',
      });
      expect(E2EEnv.odbcE2eBenchmarkRequireTimeoutCancel, isTrue);
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
        'ODBC_E2E_BENCHMARK_MAX_MS_WRITE_DML': '1500',
        'ODBC_E2E_BENCHMARK_MAX_MS_TIMEOUT_CANCEL': '2000',
        'ODBC_E2E_BENCHMARK_MAX_MS_STREAMING': '1200',
        'ODBC_E2E_BENCHMARK_MAX_MS_STREAMING_CHUNKS': '900',
        'ODBC_E2E_BENCHMARK_MAX_MS_MULTI_RESULT_PARALLEL': '1400',
        'ODBC_E2E_BENCHMARK_MAX_MS_WRITE_DML_PARALLEL': '2200',
        'ODBC_E2E_BENCHMARK_MAX_MS_BAD': 'not-int',
        'ODBC_E2E_BENCHMARK_MAX_MS_BATCH_READS': '0',
      });
      final m = E2EEnv.odbcE2eBenchmarkMaxMsByCase;
      expect(m['rpc_sql_execute_materialized'], 800);
      expect(m['rpc_sql_execute_write_dml'], 1500);
      expect(m['rpc_sql_execute_timeout_cancel'], 2000);
      expect(m['rpc_sql_execute_streaming'], 1200);
      expect(m['rpc_sql_execute_streaming_chunks'], 900);
      expect(m['rpc_sql_execute_multi_result_parallel'], 1400);
      expect(m['rpc_sql_execute_write_dml_parallel'], 2200);
      expect(m.containsKey('rpc_sql_execute_batch_reads'), isFalse);
    });

    test('odbcE2eBenchmarkMaxMsByCase parses IDEMPOTENCY_HEAVY suffix', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_MAX_MS_IDEMPOTENCY_HEAVY': '2400',
      });
      expect(
        E2EEnv
            .odbcE2eBenchmarkMaxMsByCase['rpc_sql_execute_idempotency_heavy_params'],
        2400,
      );
    });

    test('odbcE2eBenchmarkBatchCommandCount defaults and clamps', () {
      expect(E2EEnv.odbcE2eBenchmarkBatchCommandCount, 3);

      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_BATCH_COMMAND_COUNT': '40',
      });
      expect(E2EEnv.odbcE2eBenchmarkBatchCommandCount, 32);

      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_BATCH_COMMAND_COUNT': 'x',
      });
      expect(E2EEnv.odbcE2eBenchmarkBatchCommandCount, 3);
    });

    test('odbcE2eBenchmarkMaterializedMaxRows defaults and clamps', () {
      expect(E2EEnv.odbcE2eBenchmarkMaterializedMaxRows, 0);

      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_MATERIALIZED_MAX_ROWS': '500',
      });
      expect(E2EEnv.odbcE2eBenchmarkMaterializedMaxRows, 500);
    });

    test('odbcE2eBenchmarkIdempotencyWasteBytes defaults and clamps', () {
      expect(E2EEnv.odbcE2eBenchmarkIdempotencyWasteBytes, 0);

      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_IDEMPOTENCY_WASTE_BYTES': '9999999',
      });
      expect(E2EEnv.odbcE2eBenchmarkIdempotencyWasteBytes, 2 * 1024 * 1024);
    });

    test('benchmark profiles default to the tuned matrix', () {
      final resolved = E2EEnv.odbcE2eBenchmarkProfileSet;

      expect(
        resolved.source,
        OdbcE2eBenchmarkProfileSource.defaultMatrix,
      );
      expect(
        resolved.profiles.map((profile) => profile.key),
        <String>[
          'lease_p2_c4',
          'lease_p4_c8',
        ],
      );
    });

    test('benchmark profiles use explicit single profile when configured', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_POOL_MODE': 'native',
        'ODBC_E2E_BENCHMARK_POOL_SIZE': '6',
        'ODBC_E2E_BENCHMARK_CONCURRENCY': '3',
      });

      final resolved = E2EEnv.odbcE2eBenchmarkProfileSet;
      expect(resolved.source, OdbcE2eBenchmarkProfileSource.single);
      expect(resolved.profiles, hasLength(1));
      expect(resolved.profiles.single.key, 'native_p6_c3');
    });

    test('benchmark profiles parse a custom matrix', () {
      E2EEnv.seedFileEnvForTesting(<String, String>{
        'ODBC_E2E_BENCHMARK_MATRIX':
            'lease:p2:c4; lease:pool=6:concurrency=9; native:2:2',
      });

      final resolved = E2EEnv.odbcE2eBenchmarkProfileSet;
      expect(resolved.source, OdbcE2eBenchmarkProfileSource.customMatrix);
      expect(
        resolved.profiles.map((profile) => profile.key),
        <String>[
          'lease_p2_c4',
          'lease_p6_c9',
          'native_p2_c2',
        ],
      );
    });
  });
}
