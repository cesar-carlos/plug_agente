import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

import '../../tool/e2e_benchmark_profile_parse.dart';
import '../../tool/e2e_dotenv_parse.dart';

/// Environment variables for E2E and live integration tests.
///
/// Loads from .env (when present), with [Platform.environment] taking
/// precedence for shell/CI overrides.
/// Copy .env.example to .env and define the variables for the tests you run.
class E2EEnv {
  E2EEnv._();

  static bool _loaded = false;
  static const int _defaultOdbcE2eBenchmarkPoolSize = 4;
  static const int _defaultOdbcE2eBenchmarkConcurrency = 1;
  static const int _defaultOdbcE2eBenchmarkSeedRows = 32;
  static const int _defaultOdbcE2eBenchmarkMaxResultBufferMb = 32;
  static const int _defaultOdbcE2eBenchmarkStreamingChunkSizeKb = 1024;
  static const int _defaultOdbcE2eBenchmarkLoginTimeoutSeconds = 30;
  static const int _defaultOdbcE2eBenchmarkBaselineWindow = 5;

  /// Keys from project-root `.env` (same parser as `tool/check_e2e_env.dart`).
  static final Map<String, String> _fileEnv = <String, String>{};

  static File _resolveDotEnvFile() {
    var dir = Directory.current;
    for (var i = 0; i < 12; i++) {
      final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
      if (pubspec.existsSync()) {
        return File('${dir.path}${Platform.pathSeparator}.env');
      }
      final parent = dir.parent;
      if (parent.path == dir.path) {
        break;
      }
      dir = parent;
    }
    return File('.env');
  }

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;

    // flutter_dotenv's [dotenv.load] only reads via [rootBundle] (pubspec assets).
    // `.env` is not bundled (secrets); load from disk (project root via walk-up).
    try {
      final file = _resolveDotEnvFile();
      if (file.existsSync()) {
        _fileEnv
          ..clear()
          ..addAll(parseDotEnvContent(file.readAsStringSync()));
      } else {
        _fileEnv.clear();
        await dotenv.load(isOptional: true);
      }
    } on Object {
      _fileEnv.clear();
      await dotenv.load(isOptional: true);
    }

    _loaded = true;
  }

  static String? _get(String key) {
    final fromPlatform = Platform.environment[key]?.trim();
    if (fromPlatform != null && fromPlatform.isNotEmpty) return fromPlatform;
    final fromFile = _fileEnv[key]?.trim();
    if (fromFile != null && fromFile.isNotEmpty) return fromFile;
    try {
      final fromEnv = dotenv.env[key]?.trim();
      if (fromEnv != null && fromEnv.isNotEmpty) return fromEnv;
    } on Object {
      // dotenv not loaded or not initialized
    }
    return Platform.environment[key]?.trim();
  }

  static String? get(String key) => _get(key);

  /// Whether live API tests should run (RUN_LIVE_API_TESTS=true).
  static bool get runLiveApiTests => _get('RUN_LIVE_API_TESTS') == 'true';

  static const String _defaultApiBaseUrl = 'http://31.97.29.223:3000/';
  static const String _defaultTimeoutUrl = 'http://10.255.255.1:9999/';

  /// Base URL for API E2E tests (default: http://31.97.29.223:3000/).
  static String get apiTestBaseUrl => _validatedUrl(
    _get('API_TEST_BASE_URL') ?? _defaultApiBaseUrl,
    _defaultApiBaseUrl,
  );

  /// URL for timeout test (must not respond). Default: non-routable IP.
  static String get apiTestTimeoutUrl => _validatedUrl(
    _get('API_TEST_TIMEOUT_URL') ?? _defaultTimeoutUrl,
    _defaultTimeoutUrl,
  );

  /// ODBC connection string for integration tests (SQL Anywhere / Sybase).
  /// Uses ODBC_TEST_DSN or ODBC_DSN.
  static String? get odbcConnectionString =>
      _get('ODBC_TEST_DSN') ?? _get('ODBC_DSN');

  /// ODBC connection string for SQL Server E2E tests.
  /// Uses ODBC_TEST_DSN_SQL_SERVER or ODBC_DSN_SQL_SERVER.
  static String? get odbcSqlServerConnectionString =>
      _get('ODBC_TEST_DSN_SQL_SERVER') ?? _get('ODBC_DSN_SQL_SERVER');

  /// ODBC connection string for PostgreSQL E2E tests.
  /// Uses ODBC_TEST_DSN_POSTGRESQL or ODBC_DSN_POSTGRESQL.
  static String? get odbcPostgresqlConnectionString =>
      _get('ODBC_TEST_DSN_POSTGRESQL') ?? _get('ODBC_DSN_POSTGRESQL');

  /// First available ODBC DSN for generic integration tests.
  /// Prefers ODBC_TEST_DSN, then SQL Server, then PostgreSQL.
  static String? get odbcConnectionStringAny =>
      odbcConnectionString ??
      odbcSqlServerConnectionString ??
      odbcPostgresqlConnectionString;

  /// Smoke query for ODBC integration (default: SELECT 1).
  static String get odbcSmokeQuery =>
      _get('ODBC_INTEGRATION_SMOKE_QUERY') ?? 'SELECT 1';

  /// Optional SQL Anywhere smoke using TOP/START AT (pagination-shaped).
  /// When unset, a built-in query against `sys.systable` is used.
  static String? get odbcSqlAnywhereTopStartAtQuery =>
      _get('ODBC_SQL_ANYWHERE_TOP_START_AT_QUERY');

  /// When true (`ODBC_E2E_REQUIRE_MULTI_RESULT=true`), RPC live E2E fails if
  /// `sql.execute` with `multi_result` returns no `result_sets`/rows (no fallback).
  static bool get odbcE2eRequireMultiResult =>
      _get('ODBC_E2E_REQUIRE_MULTI_RESULT') == 'true';

  /// When true (`ODBC_E2E_TRANSACTIONAL_BATCH=true`), RPC live E2E runs an
  /// extra `sql.executeBatch` with `transaction: true` (validates begin/commit).
  static bool get odbcE2eTryTransactionalBatch =>
      _get('ODBC_E2E_TRANSACTIONAL_BATCH') == 'true';

  /// When true (`ODBC_E2E_BENCHMARK=true`), runs `odbc_rpc_benchmark_live_e2e_test`.
  static bool get odbcE2eBenchmarkEnabled =>
      _get('ODBC_E2E_BENCHMARK') == 'true';

  /// When true (`ODBC_E2E_BENCHMARK_RECORD=true`), benchmark E2E appends one JSON
  /// line per target to [odbcE2eBenchmarkRecordFile] (JSONL history).
  static bool get odbcE2eBenchmarkRecordEnabled =>
      _get('ODBC_E2E_BENCHMARK_RECORD') == 'true';

  /// Pool strategy used by benchmark harness (`lease` or `native`).
  static String get odbcE2eBenchmarkPoolMode {
    final value =
        _get('ODBC_E2E_BENCHMARK_POOL_MODE')?.trim().toLowerCase() ?? '';
    if (value == 'native') {
      return 'native';
    }
    return 'lease';
  }

  /// Max parallel ODBC leases / native pool size for benchmark harness.
  static int get odbcE2eBenchmarkPoolSize {
    final value = int.tryParse(_get('ODBC_E2E_BENCHMARK_POOL_SIZE') ?? '');
    if (value == null || value <= 0) {
      return _defaultOdbcE2eBenchmarkPoolSize;
    }
    return value;
  }

  /// Parallel requests per benchmark iteration.
  static int get odbcE2eBenchmarkConcurrency {
    final value = int.tryParse(_get('ODBC_E2E_BENCHMARK_CONCURRENCY') ?? '');
    if (value == null || value <= 0) {
      return _defaultOdbcE2eBenchmarkConcurrency;
    }
    return value;
  }

  /// Seed row count used by benchmark setup queries.
  static int get odbcE2eBenchmarkSeedRows {
    final value = int.tryParse(_get('ODBC_E2E_BENCHMARK_SEED_ROWS') ?? '');
    if (value == null || value <= 0) {
      return _defaultOdbcE2eBenchmarkSeedRows;
    }
    return value;
  }

  /// Result buffer size used by benchmark ODBC settings.
  static int get odbcE2eBenchmarkMaxResultBufferMb {
    final value = int.tryParse(
      _get('ODBC_E2E_BENCHMARK_MAX_RESULT_BUFFER_MB') ?? '',
    );
    if (value == null || value <= 0) {
      return _defaultOdbcE2eBenchmarkMaxResultBufferMb;
    }
    return value;
  }

  /// Streaming chunk size in KB used by benchmark ODBC settings.
  static int get odbcE2eBenchmarkStreamingChunkSizeKb {
    final value = int.tryParse(
      _get('ODBC_E2E_BENCHMARK_STREAMING_CHUNK_SIZE_KB') ?? '',
    );
    if (value == null || value <= 0) {
      return _defaultOdbcE2eBenchmarkStreamingChunkSizeKb;
    }
    return value;
  }

  /// Login timeout used by benchmark ODBC settings.
  static int get odbcE2eBenchmarkLoginTimeoutSeconds {
    final value = int.tryParse(
      _get('ODBC_E2E_BENCHMARK_LOGIN_TIMEOUT_SECONDS') ?? '',
    );
    if (value == null || value <= 0) {
      return _defaultOdbcE2eBenchmarkLoginTimeoutSeconds;
    }
    return value;
  }

  /// Path to JSONL benchmark history (project-relative or absolute).
  /// Default: `benchmark/e2e_odbc_rpc.jsonl` when recording is enabled.
  static String get odbcE2eBenchmarkRecordFile {
    final custom = _get('ODBC_E2E_BENCHMARK_FILE')?.trim();
    if (custom != null && custom.isNotEmpty) {
      return custom;
    }
    return 'benchmark${Platform.pathSeparator}e2e_odbc_rpc.jsonl';
  }

  /// Optional JSONL baseline file used for regression checks.
  static String? get odbcE2eBenchmarkBaselineFile {
    final custom = _get('ODBC_E2E_BENCHMARK_BASELINE_FILE')?.trim();
    if (custom == null || custom.isEmpty) {
      return null;
    }
    return custom;
  }

  /// Allowed latency regression over the comparable baseline mean.
  static double? get odbcE2eBenchmarkMaxRegressionPercent {
    final raw = _get('ODBC_E2E_BENCHMARK_MAX_REGRESSION_PERCENT')?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }
    final value = double.tryParse(raw);
    if (value == null || value < 0) {
      return null;
    }
    return value;
  }

  /// Fixed latency slack (ms) added to the percentual regression budget.
  static int get odbcE2eBenchmarkMaxRegressionMs {
    final value = int.tryParse(
      _get('ODBC_E2E_BENCHMARK_MAX_REGRESSION_MS') ?? '',
    );
    if (value == null || value < 0) {
      return 0;
    }
    return value;
  }

  /// Number of comparable prior records used to compute the regression baseline.
  static int get odbcE2eBenchmarkBaselineWindow {
    final value = int.tryParse(
      _get('ODBC_E2E_BENCHMARK_BASELINE_WINDOW') ?? '',
    );
    if (value == null || value <= 0) {
      return _defaultOdbcE2eBenchmarkBaselineWindow;
    }
    return value;
  }

  /// Enforce at least one timeout/cancel failure sample in benchmark case.
  static bool get odbcE2eBenchmarkRequireTimeoutCancel =>
      _get('ODBC_E2E_BENCHMARK_REQUIRE_TIMEOUT_CANCEL') == 'true';

  static const String skipReasonOdbcE2eBenchmark =
      'Defina ODBC_E2E_BENCHMARK=true no .env para rodar benchmarks ODBC RPC.';

  static ResolvedOdbcE2eBenchmarkProfiles get odbcE2eBenchmarkProfileSet {
    return resolveOdbcE2eBenchmarkProfiles(
      matrixRaw: _get('ODBC_E2E_BENCHMARK_MATRIX'),
      poolModeRaw: _get('ODBC_E2E_BENCHMARK_POOL_MODE'),
      poolSizeRaw: _get('ODBC_E2E_BENCHMARK_POOL_SIZE'),
      concurrencyRaw: _get('ODBC_E2E_BENCHMARK_CONCURRENCY'),
      defaultPoolSize: _defaultOdbcE2eBenchmarkPoolSize,
      defaultConcurrency: _defaultOdbcE2eBenchmarkConcurrency,
    );
  }

  static List<OdbcE2eBenchmarkProfile> get odbcE2eBenchmarkProfiles =>
      odbcE2eBenchmarkProfileSet.profiles;

  /// Optional context for charts: `local` | `remote` (`ODBC_E2E_BENCHMARK_DB_HOSTING`).
  static String? get odbcE2eBenchmarkDbHosting {
    final v = _get('ODBC_E2E_BENCHMARK_DB_HOSTING')?.trim().toLowerCase();
    if (v == null || v.isEmpty) {
      return null;
    }
    if (v == 'local' || v == 'remote') {
      return v;
    }
    return null;
  }

  /// Optional regression caps (ms). Keys are JSON `cases` names (see benchmark README).
  ///
  /// Env pattern: `ODBC_E2E_BENCHMARK_MAX_MS_<SUFFIX>` where suffix is uppercase
  /// e.g. `MATERIALIZED`, `BATCH_READS`, `NAMED_PARAMS`, `MULTI_RESULT`, `BATCH_TX`,
  /// `STREAMING`.
  static Map<String, int> get odbcE2eBenchmarkMaxMsByCase {
    final out = <String, int>{};
    void add(String suffix, String caseKey) {
      final raw = _get('ODBC_E2E_BENCHMARK_MAX_MS_$suffix')?.trim();
      if (raw == null || raw.isEmpty) {
        return;
      }
      final n = int.tryParse(raw);
      if (n != null && n > 0) {
        out[caseKey] = n;
      }
    }

    add('MATERIALIZED', 'rpc_sql_execute_materialized');
    add('BATCH_READS', 'rpc_sql_execute_batch_reads');
    add('NAMED_PARAMS', 'rpc_sql_execute_named_params');
    add('MULTI_RESULT', 'rpc_sql_execute_multi_result');
    add('BATCH_TX', 'rpc_sql_execute_batch_tx');
    add('WRITE_DML', 'rpc_sql_execute_write_dml');
    add('TIMEOUT_CANCEL', 'rpc_sql_execute_timeout_cancel');
    add('STREAMING', 'rpc_sql_execute_streaming');
    add('STREAMING_CHUNKS', 'rpc_sql_execute_streaming_chunks');
    add('MATERIALIZED_PARALLEL', 'rpc_sql_execute_materialized_parallel');
    add('BATCH_READS_PARALLEL', 'rpc_sql_execute_batch_reads_parallel');
    add('MULTI_RESULT_PARALLEL', 'rpc_sql_execute_multi_result_parallel');
    add('WRITE_DML_PARALLEL', 'rpc_sql_execute_write_dml_parallel');
    return out;
  }

  // --- Skip messages / helpers for test `skip:` parameter ---

  static const String skipReasonLiveApiTests =
      'Defina RUN_LIVE_API_TESTS=true no .env';

  static const String skipReasonNoOdbcDsnAny =
      'Defina ODBC_TEST_DSN, ODBC_TEST_DSN_SQL_SERVER ou ODBC_TEST_DSN_POSTGRESQL no .env';

  static const String skipReasonNoOdbcDsnPrimary =
      'Defina ODBC_TEST_DSN ou ODBC_DSN no .env';

  static const String skipReasonSqlAnywhereDriverMismatch =
      'DSN não parece SQL Anywhere; use driver SQL Anywhere ou '
      'ODBC_SQL_ANYWHERE_TOP_START_AT_QUERY';

  static const String skipReasonOdbcLongQuery =
      'Defina um DSN e ODBC_INTEGRATION_LONG_QUERY* (query longa) no .env';

  static const String skipReasonOdbcLongQueryForTarget =
      'Defina ODBC_INTEGRATION_LONG_QUERY* compativel com o DSN deste alvo no .env';

  static const String skipReasonOdbcTransactionalBatch =
      'Defina ODBC_E2E_TRANSACTIONAL_BATCH=true no .env para este teste.';

  static const String skipReasonOdbcRpcLiveMatrix =
      'Defina pelo menos um de: ODBC_TEST_DSN / ODBC_DSN, '
      'ODBC_TEST_DSN_SQL_SERVER / ODBC_DSN_SQL_SERVER, '
      'ODBC_TEST_DSN_POSTGRESQL / ODBC_DSN_POSTGRESQL.';

  /// `skip:` value: do not skip when [conditionMet] is true.
  static Object? skipUnless(bool conditionMet, String skipReason) =>
      conditionMet ? false : skipReason;

  /// Skip live API tests when `RUN_LIVE_API_TESTS` is not `true`.
  static Object? get skipUnlessLiveApiTests =>
      runLiveApiTests ? false : skipReasonLiveApiTests;

  /// Distinct ODBC DSNs for `test/live/odbc_rpc_execute_live_e2e_test.dart` (deduped).
  ///
  /// Order: primary (`ODBC_TEST_DSN` / `ODBC_DSN`), SQL Server, PostgreSQL.
  static List<({String label, String dsn})> get odbcRpcLiveTargets {
    final out = <({String label, String dsn})>[];
    final seen = <String>{};
    void add(String label, String? dsn) {
      final s = dsn?.trim();
      if (s == null || s.isEmpty) return;
      if (seen.contains(s)) return;
      seen.add(s);
      out.add((label: label, dsn: s));
    }

    add('primary', odbcConnectionString);
    add('sql_server', odbcSqlServerConnectionString);
    add('postgresql', odbcPostgresqlConnectionString);
    return out;
  }

  /// Long-running query for cancellation test.
  /// Uses DB-specific var when available, else generic ODBC_INTEGRATION_LONG_QUERY.
  static String? get odbcLongQuery {
    final conn = odbcConnectionStringAny;
    if (conn == null) return null;
    return odbcLongQueryForDsn(conn);
  }

  /// Same as [odbcLongQuery] but keyed to a specific DSN string (e.g. RPC live matrix target).
  static String? odbcLongQueryForDsn(String dsn) {
    final normalized = dsn.trim();
    if (normalized.isEmpty) return null;
    final primary = odbcConnectionString?.trim() ?? '';
    if (primary.isNotEmpty && normalized == primary) {
      return _get('ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE') ??
          _get('ODBC_INTEGRATION_LONG_QUERY');
    }
    final ss = odbcSqlServerConnectionString?.trim() ?? '';
    if (ss.isNotEmpty && normalized == ss) {
      return _get('ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER') ??
          _get('ODBC_INTEGRATION_LONG_QUERY');
    }
    final pg = odbcPostgresqlConnectionString?.trim() ?? '';
    if (pg.isNotEmpty && normalized == pg) {
      return _get('ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL') ??
          _get('ODBC_INTEGRATION_LONG_QUERY');
    }
    return _get('ODBC_INTEGRATION_LONG_QUERY');
  }

  /// Load `.env` before first use. Call at the start of `test/live/*` or other live tests.
  static Future<void> load() => _ensureLoaded();

  /// Resets loaded state for testing. Use only in test code.
  @visibleForTesting
  static void resetForTesting() {
    _loaded = false;
    _fileEnv.clear();
  }

  /// Seeds in-memory env so getters resolve without reading `.env` from disk.
  @visibleForTesting
  static void seedFileEnvForTesting(Map<String, String> env) {
    _fileEnv
      ..clear()
      ..addAll(env);
    _loaded = true;
  }

  /// Validates that [url] looks like http(s) URL. Returns false if invalid.
  static bool _isValidHttpUrl(String url) {
    final u = url.trim();
    return u.startsWith('http://') || u.startsWith('https://');
  }

  /// Returns [url] if valid, else [fallback].
  static String _validatedUrl(String url, String fallback) =>
      _isValidHttpUrl(url) ? url : fallback;
}
