import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

/// Environment variables for E2E and live integration tests.
///
/// Loads from .env (when present) and falls back to [Platform.environment].
/// Copy .env.example to .env and define the variables for the tests you run.
class E2EEnv {
  E2EEnv._();

  static bool _loaded = false;

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
        dotenv.loadFromString(
          envString: file.readAsStringSync(),
          isOptional: true,
        );
      } else {
        await dotenv.load(isOptional: true);
      }
    } on Object {
      await dotenv.load(isOptional: true);
    }

    _loaded = true;
  }

  static String? _get(String key) {
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

  /// Whether live hub Socket.IO tests should run (RUN_LIVE_HUB_TESTS=true).
  static bool get runLiveHubTests => _get('RUN_LIVE_HUB_TESTS') == 'true';

  /// Base URL for hub Socket smoke test (`E2E_HUB_URL`). `/agents` is appended when missing.
  static String? get e2eHubUrl {
    final v = _get('E2E_HUB_URL');
    if (v == null || v.trim().isEmpty) {
      return null;
    }
    return v.trim();
  }

  /// Auth token for hub Socket handshake (`E2E_HUB_TOKEN`).
  static String? get e2eHubToken {
    final v = _get('E2E_HUB_TOKEN');
    if (v == null || v.trim().isEmpty) {
      return null;
    }
    return v.trim();
  }

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
  static String? get odbcConnectionString => _get('ODBC_TEST_DSN') ?? _get('ODBC_DSN');

  /// ODBC connection string for SQL Server E2E tests.
  /// Uses ODBC_TEST_DSN_SQL_SERVER or ODBC_DSN_SQL_SERVER.
  static String? get odbcSqlServerConnectionString => _get('ODBC_TEST_DSN_SQL_SERVER') ?? _get('ODBC_DSN_SQL_SERVER');

  /// ODBC connection string for PostgreSQL E2E tests.
  /// Uses ODBC_TEST_DSN_POSTGRESQL or ODBC_DSN_POSTGRESQL.
  static String? get odbcPostgresqlConnectionString => _get('ODBC_TEST_DSN_POSTGRESQL') ?? _get('ODBC_DSN_POSTGRESQL');

  /// First available ODBC DSN for generic integration tests.
  /// Prefers ODBC_TEST_DSN, then SQL Server, then PostgreSQL.
  static String? get odbcConnectionStringAny =>
      odbcConnectionString ?? odbcSqlServerConnectionString ?? odbcPostgresqlConnectionString;

  /// Connection string for the ODBC RPC coverage E2E test
  /// (`test/integration/odbc_rpc_execute_coverage_live_e2e_test.dart`).
  ///
  /// When `ODBC_E2E_RPC_DSN` is set to a non-empty value, that string wins.
  /// Otherwise uses the same priority as [odbcConnectionStringAny].
  static String? get odbcE2eRpcConnectionString {
    final explicit = _get('ODBC_E2E_RPC_DSN');
    if (explicit != null && explicit.trim().isNotEmpty) {
      return explicit.trim();
    }
    return odbcConnectionStringAny;
  }

  /// Smoke query for ODBC integration (default: SELECT 1).
  static String get odbcSmokeQuery => _get('ODBC_INTEGRATION_SMOKE_QUERY') ?? 'SELECT 1';

  /// Optional SQL Anywhere smoke using TOP/START AT (pagination-shaped).
  /// When unset, a built-in query against `sys.systable` is used.
  static String? get odbcSqlAnywhereTopStartAtQuery => _get('ODBC_SQL_ANYWHERE_TOP_START_AT_QUERY');

  /// When true (`ODBC_E2E_REQUIRE_MULTI_RESULT=true`), RPC coverage E2E fails if
  /// `sql.execute` with `multi_result` returns no `result_sets`/rows (no fallback).
  static bool get odbcE2eRequireMultiResult => _get('ODBC_E2E_REQUIRE_MULTI_RESULT') == 'true';

  /// When true (`ODBC_E2E_TRANSACTIONAL_BATCH=true`), RPC coverage E2E runs an
  /// extra `sql.executeBatch` with `transaction: true` (validates begin/commit).
  static bool get odbcE2eTryTransactionalBatch => _get('ODBC_E2E_TRANSACTIONAL_BATCH') == 'true';

  /// When true (`ODBC_RUN_LOCK_CONTENTION_TESTS=true`), runs
  /// `odbc_lock_contention_live_integration_test` (real concurrency; opt-in).
  static bool get odbcRunLockContentionTests => _get('ODBC_RUN_LOCK_CONTENTION_TESTS') == 'true';

  /// When true (`ODBC_E2E_DML_PERF_TESTS=true`), runs `odbc_dml_perf_live_e2e_test` (insert/update/delete timing).
  static bool get odbcE2eDmlPerfTests => _get('ODBC_E2E_DML_PERF_TESTS') == 'true';

  /// Row count for DML perf E2E (`ODBC_E2E_DML_PERF_ROW_COUNT`). Default 100, clamped 10–10000.
  static int get odbcE2eDmlPerfRowCount {
    final raw = _get('ODBC_E2E_DML_PERF_ROW_COUNT');
    final parsed = raw != null ? int.tryParse(raw.trim()) : null;
    final n = parsed ?? 100;
    return n.clamp(10, 10000);
  }

  /// Optional ceiling (ms) for bulk insert phase; null = do not assert on time.
  static int? get odbcE2eDmlPerfMaxMsInsert => _parsePositiveInt('ODBC_E2E_DML_PERF_MAX_MS_INSERT');

  /// Optional ceiling (ms) for update-all phase; null = do not assert on time.
  static int? get odbcE2eDmlPerfMaxMsUpdate => _parsePositiveInt('ODBC_E2E_DML_PERF_MAX_MS_UPDATE');

  /// Optional ceiling (ms) for delete-all phase; null = do not assert on time.
  static int? get odbcE2eDmlPerfMaxMsDelete => _parsePositiveInt('ODBC_E2E_DML_PERF_MAX_MS_DELETE');

  static int? _parsePositiveInt(String key) {
    final v = _get(key);
    if (v == null || v.trim().isEmpty) {
      return null;
    }
    return int.tryParse(v.trim());
  }

  /// When true (`ODBC_E2E_DML_BULK_TESTS=true`), runs `odbc_dml_bulk_load_live_e2e_test`
  /// (large insert batches, e.g. 50k rows, then update/delete/drop, timed).
  static bool get odbcE2eDmlBulkTests => _get('ODBC_E2E_DML_BULK_TESTS') == 'true';

  /// Target row count for bulk DML E2E (`ODBC_E2E_DML_BULK_ROW_COUNT`). Default 50000, clamped 10k–200k.
  static int get odbcE2eDmlBulkRowCount {
    final raw = _get('ODBC_E2E_DML_BULK_ROW_COUNT');
    final parsed = raw != null ? int.tryParse(raw.trim()) : null;
    final n = parsed ?? 50000;
    return n.clamp(10000, 200000);
  }

  /// Insert commands per `sql.executeBatch` for bulk DML E2E (`ODBC_E2E_DML_BULK_CHUNK_SIZE`). Default 1000, clamped 32–2000.
  static int get odbcE2eDmlBulkChunkSize {
    final raw = _get('ODBC_E2E_DML_BULK_CHUNK_SIZE');
    final parsed = raw != null ? int.tryParse(raw.trim()) : null;
    final n = parsed ?? 1000;
    return n.clamp(32, 2000);
  }

  static int? get odbcE2eDmlBulkMaxMsCreate => _parsePositiveInt('ODBC_E2E_DML_BULK_MAX_MS_CREATE');

  static int? get odbcE2eDmlBulkMaxMsInsert => _parsePositiveInt('ODBC_E2E_DML_BULK_MAX_MS_INSERT');

  static int? get odbcE2eDmlBulkMaxMsUpdate => _parsePositiveInt('ODBC_E2E_DML_BULK_MAX_MS_UPDATE');

  static int? get odbcE2eDmlBulkMaxMsDelete => _parsePositiveInt('ODBC_E2E_DML_BULK_MAX_MS_DELETE');

  static int? get odbcE2eDmlBulkMaxMsDrop => _parsePositiveInt('ODBC_E2E_DML_BULK_MAX_MS_DROP');

  /// Long-running query for cancellation test.
  /// Uses DB-specific var when available, else generic ODBC_INTEGRATION_LONG_QUERY.
  static String? get odbcLongQuery {
    final conn = odbcConnectionStringAny;
    if (conn == null) return null;
    if (conn == odbcConnectionString) {
      return _get('ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE') ?? _get('ODBC_INTEGRATION_LONG_QUERY');
    }
    if (conn == odbcSqlServerConnectionString) {
      return _get('ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER') ?? _get('ODBC_INTEGRATION_LONG_QUERY');
    }
    if (conn == odbcPostgresqlConnectionString) {
      return _get('ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL') ?? _get('ODBC_INTEGRATION_LONG_QUERY');
    }
    return _get('ODBC_INTEGRATION_LONG_QUERY');
  }

  /// Load .env before first use. Call in setUpAll of integration tests.
  static Future<void> load() => _ensureLoaded();

  /// Resets loaded state for testing. Use only in test code.
  @visibleForTesting
  static void resetForTesting() {
    _loaded = false;
  }

  /// Validates that [url] looks like http(s) URL. Returns false if invalid.
  static bool _isValidHttpUrl(String url) {
    final u = url.trim();
    return u.startsWith('http://') || u.startsWith('https://');
  }

  /// Returns [url] if valid, else [fallback].
  static String _validatedUrl(String url, String fallback) => _isValidHttpUrl(url) ? url : fallback;
}
