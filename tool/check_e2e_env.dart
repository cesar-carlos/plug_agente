// ignore_for_file: avoid_print

/// Verifica se as variáveis de ambiente para testes E2E estão definidas.
///
/// Uso: `dart run tool/check_e2e_env.dart` (na raiz do projeto Flutter).
///
/// Pode ser executado de qualquer diretório; localiza a raiz do projeto
/// automaticamente. Copie `.env.example` para `.env` e defina as variáveis.
///
/// O parser partilhado com `E2EEnv` está em `tool/e2e_dotenv_parse.dart`.
library;

import 'dart:io';

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

  final env = envFile.existsSync()
      ? parseDotEnvContent(envFile.readAsStringSync())
      : <String, String>{};
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
    print('  -> test/live/api_live_test: testes serão ignorados');
  } else {
    print('  -> test/live/api_live_test: será executado');
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
    print('  -> test/live/odbc_streaming_live_test: testes serão ignorados');
  } else {
    print('  -> test/live/odbc_streaming_live_test: será executado');
  }

  print('');
  print('ODBC_INTEGRATION_SMOKE_QUERY: ${odbcSmoke ?? "SELECT 1 (default)"}');
  print(
    'ODBC_INTEGRATION_LONG_QUERY*: ${odbcLong ?? "não definido (teste de cancelamento ignorado)"}',
  );

  print('');
  print(
    'Matriz ODBC RPC live (test/live/odbc_rpc_execute_live_e2e_test.dart):',
  );
  print(
    '  Corre um grupo por connection string distinta (ordem: primary, sql_server, postgresql).',
  );
  void slot(String name, bool ok) {
    print('  - $name: ${ok ? "definido" : "não definido"}');
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
  for (final d in <String?>[odbcDsn, odbcSqlServer, odbcPostgresql]) {
    final s = d?.trim();
    if (s != null && s.isNotEmpty) distinctDsns.add(s);
  }
  if (distinctDsns.isEmpty) {
    print('  -> Nenhum grupo RPC live será executado (skip).');
  } else {
    print(
      '  -> ${distinctDsns.length} grupo(s) com DSN distinto(s) será(ão) executado(s).',
    );
  }

  print('');
  print(
    'ODBC_E2E_REQUIRE_MULTI_RESULT: ${e2eRequireMulti ? "true (falha se multi_result vier vazio)" : "não definido ou false"}',
  );
  if (e2eRequireMulti && e2eBench) {
    print(
      '  -> Com ODBC_E2E_BENCHMARK=true, o benchmark também exige payload no '
      'caso multi-result.',
    );
  }
  print(
    'ODBC_E2E_TRANSACTIONAL_BATCH: ${e2eTxBatch ? "true (lote transacional extra no E2E RPC)" : "não definido ou false"}',
  );
  if (e2eTxBatch) {
    print(
      '  -> odbc_rpc_execute_live_e2e: 4º teste (executeBatch transaction:true) '
      'será executado; em alguns drivers antigos ainda pode falhar.',
    );
  } else {
    print(
      '  -> odbc_rpc_execute_live_e2e: 4º teste (batch transacional) será '
      'ignorado (defina ODBC_E2E_TRANSACTIONAL_BATCH=true para ativar).',
    );
  }

  print('');
  print(
    'ODBC_E2E_BENCHMARK: ${e2eBench ? "true (odbc_rpc_benchmark_live_e2e)" : "não definido ou false"}',
  );
  print(
    'ODBC_E2E_BENCHMARK_RECORD: ${e2eBenchRecord ? "true (append JSONL)" : "não definido ou false"}',
  );
  print(
    'ODBC_E2E_BENCHMARK_DB_HOSTING: ${e2eBenchHosting ?? "não definido (opcional: local|remote)"}',
  );
  if (e2eBench) {
    print(
      '  -> test/live/odbc_rpc_benchmark_live_e2e_test: será executado (requer DSN na matriz RPC).',
    );
    if (e2eBenchRecord) {
      print(
        '  -> Histórico: ${get("ODBC_E2E_BENCHMARK_FILE") ?? "benchmark/e2e_odbc_rpc.jsonl (default)"}',
      );
    }
  } else {
    print(
      '  -> odbc_rpc_benchmark_live_e2e: ignorado (defina ODBC_E2E_BENCHMARK=true).',
    );
  }

  print('');
  print('Integração offline (sem .env / rede / ODBC):');
  print(
    '  - test/integration/client_token_authorization_integration_test.dart',
  );
  print('  - test/integration/connection_recovery_integration_test.dart');
  print('');
  print('Comandos úteis:');
  print('  flutter test --exclude-tags=live   # rápido: exclui test/live/*');
  print('  tool/flutter_test_no_api.bat       # Windows: mesmo que exclude-tags=live');
  print('  ./tool/flutter_test_no_api.sh      # Unix: idem');
  print('  flutter test --tags=live           # só testes com tag live');
  print(
    '  flutter test test/live/            # equivalente prático à tag live',
  );
  print('  flutter test test/integration/     # só integração offline');
  print(
    '  dart run tool/summarize_e2e_benchmark.dart  # resumo JSONL em benchmark/',
  );
}
