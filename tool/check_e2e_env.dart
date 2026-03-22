// ignore_for_file: avoid_print

import 'dart:io';

import 'e2e_benchmark_profile_parse.dart';
import 'e2e_dotenv_parse.dart';

String _projectRootPath() {
  final scriptPath = Platform.script.toFilePath();
  final toolDir = File(scriptPath).parent;
  final candidate = toolDir.parent.path;
  if (File('$candidate/pubspec.yaml').existsSync()) {
    return candidate;
  }

  var dir = Directory.current;
  for (var i = 0; i < 12; i++) {
    final pubspec = '${dir.path}${Platform.pathSeparator}pubspec.yaml';
    if (File(pubspec).existsSync()) {
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

void main() {
  final root = _projectRootPath();
  final envFile = File('$root${Platform.pathSeparator}.env');
  final exampleFile = File('$root${Platform.pathSeparator}.env.example');

  final env = envFile.existsSync()
      ? parseDotEnvContent(envFile.readAsStringSync())
      : <String, String>{};
  if (!envFile.existsSync() && exampleFile.existsSync()) {
    print('Arquivo .env nao encontrado em $root');
    print('Copie: copy .env.example .env  (Windows)');
    print('       cp .env.example .env    (Linux/macOS)\n');
  }

  String? get(String key) {
    final fromPlatform = Platform.environment[key]?.trim();
    if (fromPlatform != null && fromPlatform.isNotEmpty) {
      return fromPlatform;
    }
    final fromFile = env[key]?.trim();
    if (fromFile != null && fromFile.isNotEmpty) {
      return fromFile;
    }
    return null;
  }

  final runLiveApi = get('RUN_LIVE_API_TESTS') == 'true';
  final apiBaseUrl = get('API_TEST_BASE_URL');
  final apiTimeoutUrl = get('API_TEST_TIMEOUT_URL');

  final odbcDsn = get('ODBC_TEST_DSN') ?? get('ODBC_DSN');
  final odbcSqlServer =
      get('ODBC_TEST_DSN_SQL_SERVER') ?? get('ODBC_DSN_SQL_SERVER');
  final odbcPostgresql =
      get('ODBC_TEST_DSN_POSTGRESQL') ?? get('ODBC_DSN_POSTGRESQL');
  final odbcSmoke = get('ODBC_INTEGRATION_SMOKE_QUERY');
  final odbcLong =
      get('ODBC_INTEGRATION_LONG_QUERY') ??
      get('ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE') ??
      get('ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER') ??
      get('ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL');

  final e2eRequireMulti = get('ODBC_E2E_REQUIRE_MULTI_RESULT') == 'true';
  final e2eTxBatch = get('ODBC_E2E_TRANSACTIONAL_BATCH') == 'true';
  final e2eBench = get('ODBC_E2E_BENCHMARK') == 'true';
  final e2eBenchRecord = get('ODBC_E2E_BENCHMARK_RECORD') == 'true';
  final e2eBenchHosting = get('ODBC_E2E_BENCHMARK_DB_HOSTING');
  final e2eBenchSeedRows = get('ODBC_E2E_BENCHMARK_SEED_ROWS') ?? '32';
  final e2eBenchMaxBuffer =
      get('ODBC_E2E_BENCHMARK_MAX_RESULT_BUFFER_MB') ?? '32';
  final e2eBenchChunkKb =
      get('ODBC_E2E_BENCHMARK_STREAMING_CHUNK_SIZE_KB') ?? '1024';
  final e2eBenchLoginTimeout =
      get('ODBC_E2E_BENCHMARK_LOGIN_TIMEOUT_SECONDS') ?? '30';
  final e2eBenchBaselineFile = get('ODBC_E2E_BENCHMARK_BASELINE_FILE');
  final e2eBenchRegressionPct = get(
    'ODBC_E2E_BENCHMARK_MAX_REGRESSION_PERCENT',
  );
  final e2eBenchRegressionMs =
      get('ODBC_E2E_BENCHMARK_MAX_REGRESSION_MS') ?? '0';
  final e2eBenchBaselineWindow =
      get('ODBC_E2E_BENCHMARK_BASELINE_WINDOW') ?? '5';
  final odbcBenchRequireTimeoutCancel =
      get('ODBC_E2E_BENCHMARK_REQUIRE_TIMEOUT_CANCEL') == 'true';

  final socketTransportBench = get('SOCKET_TRANSPORT_BENCHMARK') == 'true';
  final socketTransportBenchRecord =
      get('SOCKET_TRANSPORT_BENCHMARK_RECORD') == 'true';
  final socketTransportBenchFile =
      get('SOCKET_TRANSPORT_BENCHMARK_FILE') ??
      'benchmark/socket_transport.jsonl';
  final socketTransportBenchBaseline = get(
    'SOCKET_TRANSPORT_BENCHMARK_BASELINE_FILE',
  );
  final socketTransportBenchRegression = get(
    'SOCKET_TRANSPORT_BENCHMARK_MAX_REGRESSION_PERCENT',
  );
  final socketTransportBenchRegressionMs = get(
    'SOCKET_TRANSPORT_BENCHMARK_MAX_REGRESSION_MS',
  );
  final socketTransportBenchRequireBaseline =
      get('SOCKET_TRANSPORT_BENCHMARK_REQUIRE_BASELINE') == 'true';
  final socketTransportBenchIncludeJumbo =
      get('SOCKET_TRANSPORT_BENCHMARK_INCLUDE_JUMBO') == 'true';
  final socketTransportBenchJumboBytes = get(
        'SOCKET_TRANSPORT_BENCHMARK_JUMBO_BLOB_BYTES',
      ) ??
      '286720';

  final socketTransportE2eBench =
      get('SOCKET_TRANSPORT_E2E_BENCHMARK') == 'true';
  final socketTransportE2eBenchRecord =
      get('SOCKET_TRANSPORT_E2E_BENCHMARK_RECORD') == 'true';
  final socketTransportE2eBenchFile =
      get('SOCKET_TRANSPORT_E2E_BENCHMARK_FILE') ??
      'benchmark/socket_transport_e2e.jsonl';
  final socketTransportE2eBenchBaseline = get(
    'SOCKET_TRANSPORT_E2E_BENCHMARK_BASELINE_FILE',
  );
  final socketTransportE2eBenchRegression = get(
    'SOCKET_TRANSPORT_E2E_BENCHMARK_MAX_REGRESSION_PERCENT',
  );
  final socketTransportE2eBenchRegressionMs = get(
    'SOCKET_TRANSPORT_E2E_BENCHMARK_MAX_REGRESSION_MS',
  );
  final socketTransportE2eBenchWindow = get(
    'SOCKET_TRANSPORT_E2E_BENCHMARK_BASELINE_WINDOW',
  );
  final socketTransportE2eAckFails = get(
    'SOCKET_TRANSPORT_E2E_BENCHMARK_ACK_FAILS',
  );
  final socketTransportE2eRequireBaseline =
      get('SOCKET_TRANSPORT_E2E_BENCHMARK_REQUIRE_BASELINE') == 'true';
  final socketTransportE2eStrictOutgoing =
      get('SOCKET_TRANSPORT_E2E_BENCHMARK_STRICT_OUTGOING_CONTRACT') ?? 'true';

  final retryManagerBench = get('RETRY_MANAGER_BENCHMARK') == 'true';
  final idempotencyFingerprintBench =
      get('IDEMPOTENCY_FINGERPRINT_BENCHMARK') == 'true';

  final resolvedBenchProfiles = resolveOdbcE2eBenchmarkProfiles(
    matrixRaw: get('ODBC_E2E_BENCHMARK_MATRIX'),
    poolModeRaw: get('ODBC_E2E_BENCHMARK_POOL_MODE'),
    poolSizeRaw: get('ODBC_E2E_BENCHMARK_POOL_SIZE'),
    concurrencyRaw: get('ODBC_E2E_BENCHMARK_CONCURRENCY'),
    defaultPoolSize: 4,
    defaultConcurrency: 1,
  );

  print('=== Variaveis E2E / Live Integration Tests ===\n');

  print(
    'RUN_LIVE_API_TESTS: ${runLiveApi ? "OK (true)" : "nao definido ou false"}',
  );
  print(
    'API_TEST_BASE_URL: ${apiBaseUrl ?? "http://31.97.29.223:3000/ (default)"}',
  );
  print(
    'API_TEST_TIMEOUT_URL: ${apiTimeoutUrl ?? "http://10.255.255.1:9999/ (default)"}',
  );
  print(
    runLiveApi
        ? '  -> test/live/api_live_test: sera executado'
        : '  -> test/live/api_live_test: testes serao ignorados',
  );

  print('');
  print(
    'ODBC_TEST_DSN / ODBC_DSN (SQL Anywhere): ${odbcDsn != null ? "OK" : "nao definido"}',
  );
  print(
    'ODBC_TEST_DSN_SQL_SERVER: ${odbcSqlServer != null ? "OK" : "nao definido"}',
  );
  print(
    'ODBC_TEST_DSN_POSTGRESQL: ${odbcPostgresql != null ? "OK" : "nao definido"}',
  );

  final anyOdbc = odbcDsn ?? odbcSqlServer ?? odbcPostgresql;
  final anyOdbcValid = anyOdbc != null && anyOdbc.trim().isNotEmpty;
  print(
    anyOdbcValid
        ? '  -> test/live/odbc_streaming_live_test: sera executado'
        : '  -> test/live/odbc_streaming_live_test: testes serao ignorados',
  );

  print('');
  print('ODBC_INTEGRATION_SMOKE_QUERY: ${odbcSmoke ?? "SELECT 1 (default)"}');
  print(
    'ODBC_INTEGRATION_LONG_QUERY*: ${odbcLong ?? "nao definido (teste de cancelamento ignorado)"}',
  );

  print('');
  print(
    'Matriz ODBC RPC live (test/live/odbc_rpc_execute_live_e2e_test.dart):',
  );
  print(
    '  Corre um grupo por DSN distinta (ordem: primary, sql_server, postgresql).',
  );
  void slot(String name, bool ok) {
    print('  - $name: ${ok ? "definido" : "nao definido"}');
  }

  slot(
    'primary (ODBC_TEST_DSN / ODBC_DSN)',
    odbcDsn != null && odbcDsn.trim().isNotEmpty,
  );
  slot(
    'sql_server',
    odbcSqlServer != null && odbcSqlServer.trim().isNotEmpty,
  );
  slot(
    'postgresql',
    odbcPostgresql != null && odbcPostgresql.trim().isNotEmpty,
  );

  final distinctDsns = <String>{};
  for (final dsn in <String?>[odbcDsn, odbcSqlServer, odbcPostgresql]) {
    final value = dsn?.trim();
    if (value != null && value.isNotEmpty) {
      distinctDsns.add(value);
    }
  }
  if (distinctDsns.isEmpty) {
    print('  -> Nenhum grupo RPC live sera executado (skip).');
  } else {
    print('  -> ${distinctDsns.length} grupo(s) com DSN distinta(s).');
  }

  print('');
  print(
    'ODBC_E2E_REQUIRE_MULTI_RESULT: ${e2eRequireMulti ? "true (falha se multi_result vier vazio)" : "nao definido ou false"}',
  );
  print(
    'ODBC_E2E_TRANSACTIONAL_BATCH: ${e2eTxBatch ? "true (habilita batch transacional extra)" : "nao definido ou false"}',
  );

  print('');
  print(
    'ODBC_E2E_BENCHMARK: ${e2eBench ? "true (odbc_rpc_benchmark_live_e2e)" : "nao definido ou false"}',
  );
  print(
    'ODBC_E2E_BENCHMARK_RECORD: ${e2eBenchRecord ? "true (append JSONL)" : "nao definido ou false"}',
  );
  print(
    'ODBC_E2E_BENCHMARK_DB_HOSTING: ${e2eBenchHosting ?? "nao definido (opcional: local|remote)"}',
  );
  if (e2eBench) {
    final profileMode = switch (resolvedBenchProfiles.source) {
      OdbcE2eBenchmarkProfileSource.single => 'single',
      OdbcE2eBenchmarkProfileSource.customMatrix => 'custom_matrix',
      OdbcE2eBenchmarkProfileSource.defaultMatrix => 'default_matrix',
    };
    print('ODBC_E2E_BENCHMARK profiles ($profileMode):');
    for (final profile in resolvedBenchProfiles.profiles) {
      print(
        '  - ${profile.label} '
        '(pool_mode=${profile.poolMode} '
        'pool_size=${profile.poolSize} '
        'concurrency=${profile.concurrency})',
      );
    }
    print(
      '  shared: '
      'seed_rows=$e2eBenchSeedRows '
      'max_result_buffer_mb=$e2eBenchMaxBuffer '
      'streaming_chunk_size_kb=$e2eBenchChunkKb '
      'login_timeout_seconds=$e2eBenchLoginTimeout',
    );
    if (e2eBenchRecord) {
      print(
        '  -> Historico: ${get("ODBC_E2E_BENCHMARK_FILE") ?? "benchmark/e2e_odbc_rpc.jsonl (default)"}',
      );
    }
    if (e2eBenchBaselineFile != null && e2eBenchRegressionPct != null) {
      print(
        '  -> Regressao vs baseline: '
        'file=$e2eBenchBaselineFile '
        'max_regression_pct=$e2eBenchRegressionPct '
        'max_regression_ms=$e2eBenchRegressionMs '
        'window=$e2eBenchBaselineWindow',
      );
    }
    print(
      'ODBC_E2E_BENCHMARK_REQUIRE_TIMEOUT_CANCEL: '
      '${odbcBenchRequireTimeoutCancel ? "true (exige timeout/cancel observavel)" : "nao definido ou false"}',
    );
  } else {
    print(
      '  -> odbc_rpc_benchmark_live_e2e: ignorado (defina ODBC_E2E_BENCHMARK=true).',
    );
  }

  print('');
  print(
    'SOCKET_TRANSPORT_BENCHMARK: ${socketTransportBench ? "true (transport_pipeline_benchmark)" : "nao definido ou false"}',
  );
  print(
    'SOCKET_TRANSPORT_BENCHMARK_RECORD: ${socketTransportBenchRecord ? "true (append JSONL)" : "nao definido ou false"}',
  );
  if (socketTransportBench) {
    print(
      '  -> test/infrastructure/codecs/transport_pipeline_benchmark_test.dart: sera executado.',
    );
    if (socketTransportBenchRecord) {
      print('  -> Historico transporte: $socketTransportBenchFile');
    }
    if (socketTransportBenchBaseline != null &&
        socketTransportBenchRegression != null) {
      print(
        '  -> Regressao transporte vs baseline: '
        'file=$socketTransportBenchBaseline '
        'max_regression_pct=$socketTransportBenchRegression '
        'max_regression_ms=${socketTransportBenchRegressionMs ?? "8"} '
        'require_baseline=$socketTransportBenchRequireBaseline',
      );
    }
    print(
      '  -> Jumbo isolate roundtrip: include_jumbo=$socketTransportBenchIncludeJumbo '
      'jumbo_blob_bytes=$socketTransportBenchJumboBytes',
    );
  } else {
    print(
      '  -> transport_pipeline_benchmark_test: ignorado (defina SOCKET_TRANSPORT_BENCHMARK=true).',
    );
  }

  print('');
  print(
    'SOCKET_TRANSPORT_E2E_BENCHMARK: ${socketTransportE2eBench ? "true (socket_transport_e2e_benchmark)" : "nao definido ou false"}',
  );
  print(
    'SOCKET_TRANSPORT_E2E_BENCHMARK_RECORD: ${socketTransportE2eBenchRecord ? "true (append JSONL)" : "nao definido ou false"}',
  );
  if (socketTransportE2eBench) {
    print(
      '  -> test/infrastructure/external_services/socket_transport_e2e_benchmark_test.dart: sera executado.',
    );
    if (socketTransportE2eBenchRecord) {
      print('  -> Historico transporte E2E: $socketTransportE2eBenchFile');
    }
    if (socketTransportE2eAckFails != null) {
      print('  -> Perfil: ack_fails=$socketTransportE2eAckFails');
    }
    print(
      '  -> strict_outgoing_contract: $socketTransportE2eStrictOutgoing '
      '(defina SOCKET_TRANSPORT_E2E_BENCHMARK_STRICT_OUTGOING_CONTRACT=false para desligar)',
    );
    if (socketTransportE2eBenchBaseline != null &&
        socketTransportE2eBenchRegression != null) {
      print(
        '  -> Regressao transporte E2E vs baseline: '
        'file=$socketTransportE2eBenchBaseline '
        'max_regression_pct=$socketTransportE2eBenchRegression '
        'max_regression_ms=${socketTransportE2eBenchRegressionMs ?? "2"} '
        'window=${socketTransportE2eBenchWindow ?? "5"} '
        'require_baseline=$socketTransportE2eRequireBaseline',
      );
    }
  } else {
    print(
      '  -> socket_transport_e2e_benchmark_test: ignorado (defina SOCKET_TRANSPORT_E2E_BENCHMARK=true).',
    );
  }

  print('');
  print(
    'RETRY_MANAGER_BENCHMARK: ${retryManagerBench ? "true (retry_manager_benchmark_test)" : "nao definido ou false"}',
  );
  print(
    'IDEMPOTENCY_FINGERPRINT_BENCHMARK: ${idempotencyFingerprintBench ? "true (idempotency_fingerprint_benchmark_test)" : "nao definido ou false"}',
  );

  print('');
  print('Integracao offline (sem .env / rede / ODBC):');
  print(
    '  - test/integration/client_token_authorization_integration_test.dart',
  );
  print('  - test/integration/connection_recovery_integration_test.dart');
  print('');
  print('Comandos uteis:');
  print('  flutter test --exclude-tags=live');
  print('  tool/flutter_test_no_api.bat');
  print('  ./tool/flutter_test_no_api.sh');
  print('  flutter test --tags=live');
  print('  flutter test test/live/');
  print('  flutter test test/integration/');
  print('  dart run tool/summarize_e2e_benchmark.dart');
}
