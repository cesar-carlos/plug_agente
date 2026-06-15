// ignore_for_file: avoid_print

/// Verifica se as variáveis de ambiente para testes E2E estão definidas.
///
/// Uso: `dart run tool/e2e/check_e2e_env.dart` (na raiz do projeto Flutter).
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

/// Usage: dart run tool/e2e/check_e2e_env.dart [--fail-if-missing-odbc] [--fail-if-missing-live-api] [--fail-if-missing-hub]
///
/// Without flags: prints diagnostic report and exits 0 (informational only).
/// With flags: exits 1 if the specified test category has no configured vars.
/// Useful as a CI gate: fail fast when required live-test vars are absent.
void main(List<String> args) {
  final failIfMissingOdbc = args.contains('--fail-if-missing-odbc');
  final failIfMissingLiveApi = args.contains('--fail-if-missing-live-api');
  final failIfMissingHub = args.contains('--fail-if-missing-hub');

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
  final apiBaseUrlOk = apiBaseUrl != null && apiBaseUrl.trim().isNotEmpty;
  if (!runLiveApi) {
    print('  -> api_test: testes serão ignorados');
  } else if (!apiBaseUrlOk) {
    print('  -> api_test: testes serão ignorados (defina API_TEST_BASE_URL)');
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

  final runLiveHubSigning = get('RUN_LIVE_HUB_SIGNING_TESTS') == 'true';
  final runLiveHubAgentActions = get('RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS') == 'true';
  final hubSigningKey = get('PAYLOAD_SIGNING_KEY');
  final hubSigningKeyId = get('PAYLOAD_SIGNING_KEY_ID') ?? get('PAYLOAD_SIGNING_ACTIVE_KEY_ID');
  final hubSigningOk =
      hubSigningKey != null &&
      hubSigningKey.trim().isNotEmpty &&
      hubSigningKeyId != null &&
      hubSigningKeyId.trim().isNotEmpty;
  final hubAgentActionReady = runLiveHub && hubUrlOk && hubTokenOk && runLiveHubSigning && hubSigningOk;

  print('');
  print(
    'RUN_LIVE_HUB_SIGNING_TESTS: ${runLiveHubSigning ? "OK (true)" : "não definido ou false"}',
  );
  print(
    'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS: ${runLiveHubAgentActions ? "OK (true)" : "não definido ou false"}',
  );
  print(
    'E2E_HUB_EXPECT_AGENT_ACTIONS_CAPABILITY: ${get("E2E_HUB_EXPECT_AGENT_ACTIONS_CAPABILITY") == "true" ? "true" : "não definido ou false"}',
  );
  print(
    'E2E_HUB_EXPECT_AGENT_ACTION_RPC: ${get("E2E_HUB_EXPECT_AGENT_ACTION_RPC") == "true" ? "true" : "não definido ou false"}',
  );
  if (runLiveHubAgentActions && hubAgentActionReady) {
    print('  -> hub_agent_action_rpc_live_e2e_test: será executado');
  } else if (!runLiveHubAgentActions) {
    print(
      '  -> hub_agent_action_rpc_live_e2e_test: ignorado '
      '(defina RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS=true)',
    );
  } else {
    print(
      '  -> hub_agent_action_rpc_live_e2e_test: ignorado '
      '(requer RUN_LIVE_HUB_TESTS, E2E_HUB_URL/TOKEN, RUN_LIVE_HUB_SIGNING_TESTS e chaves HMAC)',
    );
  }
  if (!hubSigningOk && (runLiveHubSigning || runLiveHubAgentActions)) {
    print(
      'PAYLOAD_SIGNING_KEY + PAYLOAD_SIGNING_KEY_ID (ou PAYLOAD_SIGNING_ACTIVE_KEY_ID): '
      '${hubSigningOk ? "OK" : "incompleto"}',
    );
    print(
      '  -> signing: dart run tool/e2e/promote_e2e_signing_from_monorepo_env.dart '
      'ou dart run tool/e2e/generate_dev_e2e_signing.dart --write (mesmo par em plug_server/.env)',
    );
    print('  -> validate: dart run tool/e2e/validate_live_hub_agent_actions_env.dart');
  }

  final comStubEnabled = get('AGENT_ACTION_COM_STUB_ENABLED') == 'true';
  final comStubProgId = get('AGENT_ACTION_COM_STUB_PROG_ID');
  final comStubMember = get('AGENT_ACTION_COM_STUB_MEMBER_NAME');
  final comStubProgOk = comStubProgId != null && comStubProgId.trim().isNotEmpty;
  final comStubMemberOk = comStubMember != null && comStubMember.trim().isNotEmpty;
  print('');
  print(
    'AGENT_ACTION_COM_STUB_ENABLED: ${comStubEnabled ? "true (homologacao DI)" : "não definido ou false"}',
  );
  print('AGENT_ACTION_COM_STUB_PROG_ID: ${comStubProgOk ? comStubProgId : "não definido"}');
  print(
    'AGENT_ACTION_COM_STUB_MEMBER_NAME: ${comStubMemberOk ? comStubMember : "não definido"}',
  );
  if (comStubEnabled && comStubProgOk && comStubMemberOk) {
    print('  -> COM stub handler: registrado no bootstrap quando o app carregar .env');
  } else if (comStubEnabled) {
    print('  -> COM stub: incompleto (defina PROG_ID e MEMBER_NAME)');
  } else {
    print('  -> COM stub: desligado (handlers de producao devem ser registrados no codigo)');
  }

  final elevatedExe = get('ELEVATED_ACTION_RUNNER_EXE');
  final elevatedExeOk = elevatedExe != null && elevatedExe.isNotEmpty && File(elevatedExe).existsSync();
  final defaultElevatedBuild = File(
    '$root${Platform.pathSeparator}build${Platform.pathSeparator}elevated_runner${Platform.pathSeparator}plug_agente_elevated_runner.exe',
  );
  print('');
  print('ELEVATED_ACTION_RUNNER_EXE: ${elevatedExe ?? "(nao definido — tenta exe ao lado do plug_agente.exe)"}');
  if (elevatedExeOk) {
    print('  -> helper elevado: caminho do .env existe');
  } else if (defaultElevatedBuild.existsSync()) {
    print(
      '  -> build local encontrado: ${defaultElevatedBuild.path} (defina ELEVATED_ACTION_RUNNER_EXE ou copie para o runner Release)',
    );
  } else {
    print('  -> helper elevado: rode python tool/elevated/build_elevated_runner.py antes de homologar elevado na UI');
  }
  print('  -> homologacao elevada: python tool/elevated/homologate_elevated_runner.py --build [--run-unit-tests]');
  print('     manual UI/UAC: docs/testing/e2e_setup.md');

  _printOdbcLoadAndCircuitBreakerWarnings(
    runBurst: runBurst,
    dmlPerf: dmlPerf,
    dmlBulk: dmlBulk,
    dmlStress: get('ODBC_E2E_DML_STRESS_TESTS') == 'true',
    runLockContention: runLockContention,
    runLiveHub: runLiveHub,
    runLiveHubAgentActions: runLiveHubAgentActions,
    odbcE2eRpc: odbcE2eRpc,
    odbcDsn: odbcDsn,
  );

  print('');
  print(
    'Para rodar: flutter test test/integration/ test/infrastructure/external_services/api_test.dart',
  );
  print(
    'Hub agent.action (opt-in): flutter test test/integration/hub_agent_action_rpc_live_e2e_test.dart --tags live',
  );
  print(
    'Agent actions local gate (sem Hub): python tool/agent_actions/homologate_hub_agent_actions.py --run-contract-tests',
  );
  print('Agent actions live Hub env only: dart run tool/e2e/validate_live_hub_agent_actions_env.dart');
  print(
    'Agent actions live Hub full: python tool/agent_actions/homologate_hub_agent_actions.py --validate-live-env --run-contract-tests --run-live-tests',
  );
  print(
    'Elevated (unit): flutter test test/infrastructure/actions/elevated_action_runner_installer_test.dart',
  );
  print('Burst (opt-in): flutter test test/integration/sql_queue_burst_test.dart');

  // CI gate: exit(1) when the caller requires specific categories to be configured.
  var shouldFail = false;
  if (failIfMissingOdbc && !anyOdbcValid) {
    print('\n[FAIL] --fail-if-missing-odbc: no ODBC DSN configured.');
    shouldFail = true;
  }
  if (failIfMissingLiveApi && !runLiveApi) {
    print('\n[FAIL] --fail-if-missing-live-api: RUN_LIVE_API_TESTS is not true.');
    shouldFail = true;
  }
  if (failIfMissingHub && !runLiveHub) {
    print('\n[FAIL] --fail-if-missing-hub: RUN_LIVE_HUB_TESTS is not true or hub URL/token absent.');
    shouldFail = true;
  }
  if (shouldFail) {
    exit(1);
  }
}

void _printOdbcLoadAndCircuitBreakerWarnings({
  required bool runBurst,
  required bool dmlPerf,
  required bool dmlBulk,
  required bool dmlStress,
  required bool runLockContention,
  required bool runLiveHub,
  required bool runLiveHubAgentActions,
  required String? odbcE2eRpc,
  required String? odbcDsn,
}) {
  final aggressive = <String>[
    if (runBurst) 'RUN_ODBC_BURST_TESTS',
    if (dmlPerf) 'ODBC_E2E_DML_PERF_TESTS',
    if (dmlBulk) 'ODBC_E2E_DML_BULK_TESTS',
    if (dmlStress) 'ODBC_E2E_DML_STRESS_TESTS',
    if (runLockContention) 'ODBC_RUN_LOCK_CONTENTION_TESTS',
    if (runLiveHub) 'RUN_LIVE_HUB_TESTS',
    if (runLiveHubAgentActions) 'RUN_LIVE_HUB_AGENT_ACTION_RPC_TESTS',
  ];

  print('');
  print('=== Carga ODBC / circuit breaker ===');
  if (aggressive.isEmpty) {
    print('Nenhum opt-in agressivo de ODBC/Hub detectado.');
    return;
  }

  print(
    'Opt-ins agressivos ativos (${aggressive.length}): ${aggressive.join(', ')}',
  );
  print(
    '  -> Para smoke diario, mantenha apenas ODBC_TEST_DSN e desative burst/bulk/stress/lock.',
  );
  print(
    '  -> Erro -32106 com odbc_reason=circuit_breaker_open e efeito cascata: apos '
    '5 falhas reais de conexao ODBC, pedidos seguintes falham rapido por ~30s '
    '(CIRCUIT_BREAKER_RESET_SEC).',
  );
  print(
    '  -> Se o agente desktop estiver conectado ao Hub, reinicie-o apos abrir o '
    'circuit breaker ou aguarde o reset; testes E2E in-process nao compartilham '
    'o breaker do agente em execucao.',
  );

  final dsnHint = _odbcDsnTargetHint(odbcE2eRpc ?? odbcDsn);
  if (dsnHint != null) {
    print('  -> DSN E2E efetivo (sem credenciais): $dsnHint');
    print(
      '  -> Se o agente usa outro DBN/HOST:porta (ex. CasaDoMel:2660 vs VL:2650), '
      'alinhe ODBC_E2E_RPC_DSN ao agente ou corrija payload.database do Hub.',
    );
  }
}

String? _odbcDsnTargetHint(String? dsn) {
  if (dsn == null || dsn.trim().isEmpty) {
    return null;
  }
  final normalized = dsn.trim();
  final dbn = RegExp('DBN=([^;]+)', caseSensitive: false).firstMatch(normalized)?.group(1);
  final host = RegExp('HOST=([^;]+)', caseSensitive: false).firstMatch(normalized)?.group(1);
  final database = RegExp('Database=([^;]+)', caseSensitive: false).firstMatch(normalized)?.group(1);
  final server = RegExp('Server=([^;]+)', caseSensitive: false).firstMatch(normalized)?.group(1);
  final parts = <String>[
    if (dbn != null) 'DBN=$dbn',
    if (host != null) 'HOST=$host',
    if (database != null) 'Database=$database',
    if (server != null) 'Server=$server',
  ];
  return parts.isEmpty ? '(DSN definido)' : parts.join('; ');
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
