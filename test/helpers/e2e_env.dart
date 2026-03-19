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

  static Future<void> _ensureLoaded() async {
    if (_loaded) return;
    await dotenv.load(isOptional: true);
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

  /// Long-running query for cancellation test.
  /// Uses DB-specific var when available, else generic ODBC_INTEGRATION_LONG_QUERY.
  static String? get odbcLongQuery {
    final conn = odbcConnectionStringAny;
    if (conn == null) return null;
    if (conn == odbcConnectionString) {
      return _get('ODBC_INTEGRATION_LONG_QUERY_SQL_ANYWHERE') ??
          _get('ODBC_INTEGRATION_LONG_QUERY');
    }
    if (conn == odbcSqlServerConnectionString) {
      return _get('ODBC_INTEGRATION_LONG_QUERY_SQL_SERVER') ??
          _get('ODBC_INTEGRATION_LONG_QUERY');
    }
    if (conn == odbcPostgresqlConnectionString) {
      return _get('ODBC_INTEGRATION_LONG_QUERY_POSTGRESQL') ??
          _get('ODBC_INTEGRATION_LONG_QUERY');
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
  static String _validatedUrl(String url, String fallback) =>
      _isValidHttpUrl(url) ? url : fallback;
}
