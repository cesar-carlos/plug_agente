// ignore_for_file: avoid_print

/// Verifica se as variáveis de ambiente para testes E2E estão definidas.
///
/// Uso: `dart run tool/check_e2e_env.dart` (na raiz do projeto Flutter).
///
/// Pode ser executado de qualquer diretório; localiza a raiz do projeto
/// automaticamente. Copie `.env.example` para `.env` e defina as variáveis.
///
/// O parser segue o mesmo estilo de chave=valor que o `E2EEnv` usa com
/// `loadFromString` (primeiro `=` separa chave e valor; valor pode conter `=`).
library;

import 'dart:io';

String _projectRootPath() {
  final scriptPath = Platform.script.toFilePath();
  final toolDir = File(scriptPath).parent;
  final candidate = toolDir.parent.path;
  if (File('$candidate/pubspec.yaml').existsSync()) {
    return candidate;
  }
  var dir = Directory.current;
  for (var i = 0; i < 12; i++) {
    final p = '${dir.path}${Platform.pathSeparator}pubspec.yaml';
    if (File(p).existsSync()) {
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

  final env = _loadEnv(envFile);
  if (!envFile.existsSync() && exampleFile.existsSync()) {
    print('Arquivo .env nao encontrado em $root');
    print('Copie: copy .env.example .env  (Windows)');
    print('       cp .env.example .env    (Linux/macOS)\n');
  }

  String? get(String key) {
    final v = env[key]?.trim();
    if (v != null && v.isNotEmpty) return v;
    return Platform.environment[key]?.trim();
  }

  final runLiveApi = get('RUN_LIVE_API_TESTS') == 'true';
  final apiBaseUrl = get('API_TEST_BASE_URL');
  final apiTimeoutUrl = get('API_TEST_TIMEOUT_URL');
  final odbcDsn = get('ODBC_TEST_DSN') ?? get('ODBC_DSN');
  final odbcSqlServer = get('ODBC_TEST_DSN_SQL_SERVER') ?? get('ODBC_DSN_SQL_SERVER');
  final odbcPostgresql = get('ODBC_TEST_DSN_POSTGRESQL') ?? get('ODBC_DSN_POSTGRESQL');
  final odbcE2eRpcExplicit = get('ODBC_E2E_RPC_DSN');
  final odbcE2eRpc = (odbcE2eRpcExplicit != null && odbcE2eRpcExplicit.trim().isNotEmpty)
      ? odbcE2eRpcExplicit.trim()
      : (odbcDsn ?? odbcSqlServer ?? odbcPostgresql);
  final odbcSmoke = get('ODBC_INTEGRATION_SMOKE_QUERY');
  final odbcLong =
      get('ODBC_INTEGRATION_LONG_QUERY') ??
      get('ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE') ??
      get('ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER') ??
      get('ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL');
  final e2eRequireMulti = get('ODBC_E2E_REQUIRE_MULTI_RESULT') == 'true';
  final e2eTxBatch = get('ODBC_E2E_TRANSACTIONAL_BATCH') == 'true';
  final runLockContention = get('ODBC_RUN_LOCK_CONTENTION_TESTS') == 'true';
  final runLiveHub = get('RUN_LIVE_HUB_TESTS') == 'true';
  final e2eHubUrl = get('E2E_HUB_URL');
  final e2eHubToken = get('E2E_HUB_TOKEN');
  final hubUrlOk = e2eHubUrl != null && e2eHubUrl.trim().isNotEmpty;
  final hubTokenOk = e2eHubToken != null && e2eHubToken.trim().isNotEmpty;

  print('=== Variáveis E2E / Live Integration Tests ===\n');

  print(
    'RUN_LIVE_API_TESTS: ${runLiveApi ? "OK (true)" : "não definido ou false"}',
  );
  print(
    'API_TEST_BASE_URL: ${apiBaseUrl ?? "http://31.97.29.223:3000/ (default)"}',
  );
  print(
    'API_TEST_TIMEOUT_URL: ${apiTimeoutUrl ?? "http://10.255.255.1:9999/ (default)"}',
  );
  if (!runLiveApi) {
    print('  -> api_test: testes serão ignorados');
  } else {
    print('  -> api_test: será executado');
  }

  print('');
  print(
    'ODBC_TEST_DSN / ODBC_DSN (SQL Anywhere): ${odbcDsn != null ? "OK" : "não definido"}',
  );
  print(
    'ODBC_TEST_DSN_SQL_SERVER: ${odbcSqlServer != null ? "OK" : "não definido"}',
  );
  print(
    'ODBC_TEST_DSN_POSTGRESQL: ${odbcPostgresql != null ? "OK" : "não definido"}',
  );
  final anyOdbc = odbcDsn ?? odbcSqlServer ?? odbcPostgresql;
  final anyOdbcValid = anyOdbc != null && anyOdbc.trim().isNotEmpty;
  if (!anyOdbcValid) {
    print('  -> odbc_streaming_live_integration_test: testes serão ignorados');
  } else {
    print('  -> odbc_streaming_live_integration_test: será executado');
  }
  if (odbcE2eRpcExplicit != null && odbcE2eRpcExplicit.trim().isNotEmpty) {
    print('ODBC_E2E_RPC_DSN: OK (override do E2E RPC)');
  } else {
    print('ODBC_E2E_RPC_DSN: (vazio — usa fallback Anywhere → SQL Server → PostgreSQL)');
  }
  if (odbcE2eRpc == null || odbcE2eRpc.trim().isEmpty) {
    print('  -> odbc_rpc_execute_coverage_live_e2e_test: testes serão ignorados (sem DSN RPC)');
  } else {
    print('  -> odbc_rpc_execute_coverage_live_e2e_test: será executado');
  }

  final dmlPerf = get('ODBC_E2E_DML_PERF_TESTS') == 'true';
  final dmlRows = get('ODBC_E2E_DML_PERF_ROW_COUNT');
  print('');
  print(
    'ODBC_E2E_DML_PERF_TESTS: ${dmlPerf ? "true (insert/update/delete em lote)" : "não definido ou false"}',
  );
  print(
    'ODBC_E2E_DML_PERF_ROW_COUNT: ${dmlRows ?? "100 (default se ativar)"}',
  );
  if (dmlPerf && odbcE2eRpc != null && odbcE2eRpc.trim().isNotEmpty) {
    print('  -> odbc_dml_perf_live_e2e_test: será executado');
  } else {
    print(
      '  -> odbc_dml_perf_live_e2e_test: ignorado (defina ODBC_E2E_DML_PERF_TESTS=true e um DSN RPC)',
    );
  }

  final dmlBulk = get('ODBC_E2E_DML_BULK_TESTS') == 'true';
  final dmlBulkRows = get('ODBC_E2E_DML_BULK_ROW_COUNT');
  final dmlBulkChunk = get('ODBC_E2E_DML_BULK_CHUNK_SIZE');
  print('');
  print('ODBC_E2E_DML_BULK_TESTS: ${dmlBulk ? "true (carga 10k–200k rows)" : "não definido ou false"}');
  print('ODBC_E2E_DML_BULK_ROW_COUNT: ${dmlBulkRows ?? "50000 (default se ativar)"}');
  print('ODBC_E2E_DML_BULK_CHUNK_SIZE: ${dmlBulkChunk ?? "1000 (default se ativar)"}');
  if (dmlBulk && odbcE2eRpc != null && odbcE2eRpc.trim().isNotEmpty) {
    print('  -> odbc_dml_bulk_load_live_e2e_test: será executado (pode demorar muitos minutos)');
  } else {
    print(
      '  -> odbc_dml_bulk_load_live_e2e_test: ignorado (defina ODBC_E2E_DML_BULK_TESTS=true e DSN)',
    );
  }

  print('');
  print('ODBC_INTEGRATION_SMOKE_QUERY: ${odbcSmoke ?? "SELECT 1 (default)"}');
  print(
    'ODBC_INTEGRATION_LONG_QUERY*: ${odbcLong ?? "não definido (teste de cancelamento ignorado)"}',
  );

  print('');
  print(
    'ODBC_E2E_REQUIRE_MULTI_RESULT: ${e2eRequireMulti ? "true (falha se multi_result vier vazio)" : "não definido ou false"}',
  );
  print(
    'ODBC_E2E_TRANSACTIONAL_BATCH: ${e2eTxBatch ? "true (lote transacional extra no E2E RPC)" : "não definido ou false"}',
  );
  if (e2eTxBatch) {
    print(
      '  -> odbc_rpc_execute_coverage: 3º teste (executeBatch transaction:true) '
      'será executado; em alguns drivers antigos ainda pode falhar.',
    );
  } else {
    print(
      '  -> odbc_rpc_execute_coverage: 3º teste (batch transacional) será '
      'ignorado (defina ODBC_E2E_TRANSACTIONAL_BATCH=true para ativar).',
    );
  }

  print('');
  print(
    'ODBC_RUN_LOCK_CONTENTION_TESTS: ${runLockContention ? "true (concorrência/locks real)" : "não definido ou false"}',
  );
  if (runLockContention && anyOdbcValid) {
    print('  -> odbc_lock_contention_live_integration_test: será executado');
  } else if (!runLockContention) {
    print(
      '  -> odbc_lock_contention_live_integration_test: ignorado '
      '(defina ODBC_RUN_LOCK_CONTENTION_TESTS=true e um DSN)',
    );
  } else {
    print('  -> odbc_lock_contention_live_integration_test: ignorado (sem DSN)');
  }

  final runBurst = get('RUN_ODBC_BURST_TESTS') == 'true';
  print('');
  print(
    'RUN_ODBC_BURST_TESTS: ${runBurst ? "true (50 pedidos paralelos na fila)" : "não definido ou false"}',
  );
  final rpcOk = odbcE2eRpc != null && odbcE2eRpc.trim().isNotEmpty;
  final longOk = odbcLong != null && odbcLong.trim().isNotEmpty;
  if (runBurst && rpcOk && longOk) {
    print('  -> sql_queue_burst_test: será executado (DSN RPC + query longa OK)');
  } else if (!runBurst) {
    print(
      '  -> sql_queue_burst_test: ignorado (defina RUN_ODBC_BURST_TESTS=true, DSN RPC e '
      'ODBC_INTEGRATION_LONG_QUERY* ou ODBC_INTEGRATION_LONG_QUERY)',
    );
  } else if (!rpcOk) {
    print('  -> sql_queue_burst_test: ignorado (sem DSN RPC — ODBC_E2E_RPC_DSN ou fallback ODBC)');
  } else if (!longOk) {
    print(
      '  -> sql_queue_burst_test: ignorado (query longa ausente — ODBC_INTEGRATION_LONG_QUERY* '
      'ou ODBC_INTEGRATION_LONG_QUERY; ver docs/testing/e2e_setup.md)',
    );
  }

  print('');
  print('RUN_LIVE_HUB_TESTS: ${runLiveHub ? "OK (true)" : "não definido ou false"}');
  print('E2E_HUB_URL: ${hubUrlOk ? "OK" : "não definido"}');
  print('E2E_HUB_TOKEN: ${hubTokenOk ? "OK" : "não definido"}');
  if (runLiveHub && hubUrlOk && hubTokenOk) {
    print('  -> hub_socket_live_e2e_test: será executado');
  } else {
    print(
      '  -> hub_socket_live_e2e_test: ignorado (defina RUN_LIVE_HUB_TESTS=true, '
      'E2E_HUB_URL e E2E_HUB_TOKEN)',
    );
  }

  print('');
  print(
    'Para rodar: flutter test test/integration/ test/infrastructure/external_services/api_test.dart',
  );
  print('Burst (opt-in): flutter test test/integration/sql_queue_burst_test.dart');
}

Map<String, String> _loadEnv(File file) {
  final result = <String, String>{};
  if (!file.existsSync()) return result;
  for (final line in file.readAsLinesSync()) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final idx = trimmed.indexOf('=');
    if (idx <= 0) continue;
    final key = trimmed.substring(0, idx).trim();
    var value = trimmed.substring(idx + 1).trim();
    if (value.startsWith('"') && value.endsWith('"')) {
      value = value.substring(1, value.length - 1);
    } else if (value.startsWith("'") && value.endsWith("'")) {
      value = value.substring(1, value.length - 1);
    }
    result[key] = value;
  }
  return result;
}
