import 'package:odbc_fast/odbc_fast.dart' show OdbcUsageProfile;
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/sql_command.dart';
import 'package:plug_agente/domain/repositories/i_connection_pool.dart';
import 'package:plug_agente/domain/validation/sql_validator.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/config/odbc_usage_profile_config.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_dsn_native_compatible_timeout_cache.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';

/// Decides whether a query/batch can use the experimental native-compatible
/// pooled acquire path instead of the default lease path.
///
/// Extracted from `OdbcDatabaseGateway` to isolate the SQL-shape heuristics and
/// the env-driven allowlist (with its TTL cache) behind a focused, testable
/// contract. The pure classification helpers are static; the instance holds
/// only the allowlist cache.
final class NativeCompatibleAcquirePolicy {
  NativeCompatibleAcquirePolicy({
    FeatureFlags? featureFlags,
    String allowlistEnvName = _defaultAllowlistEnvName,
    Duration allowlistCacheTtl = _defaultAllowlistCacheTtl,
    OdbcDsnNativeCompatibleTimeoutCache? dsnTimeoutCache,
  }) : _featureFlags = featureFlags,
       _allowlistEnvName = allowlistEnvName,
       _allowlistCacheTtl = allowlistCacheTtl,
       _dsnTimeoutCache = dsnTimeoutCache ?? OdbcDsnNativeCompatibleTimeoutCache();

  final FeatureFlags? _featureFlags;
  final String _allowlistEnvName;
  final Duration _allowlistCacheTtl;
  final OdbcDsnNativeCompatibleTimeoutCache _dsnTimeoutCache;

  static const String _defaultAllowlistEnvName = 'ODBC_NATIVE_COMPATIBLE_SQL_ALLOWLIST';
  static const Duration _defaultAllowlistCacheTtl = Duration(seconds: 10);

  String? _cachedAllowlistRaw;
  Set<String> _cachedAllowlist = const <String>{};
  DateTime? _cachedAllowlistExpiresAt;

  static final RegExp _whitespaceRun = RegExp(r'\s+');
  static final RegExp _trailingSemicolons = RegExp(r';+$');
  static final RegExp _probeQuery = RegExp(
    r'^select\s+(?:1|0|null|current_timestamp|getdate\(\)|@@version|version\(\))(?:\s+(?:as\s+)?[a-z_][a-z0-9_]*)?$',
  );
  static final RegExp _wildcardProjection = RegExp(
    r'\bselect\s+(?:top\s*\(?\s*\d+\s*\)?\s+)?\*[\s,]',
  );
  static final RegExp _explicitRowLimit = RegExp(
    r'(?:\btop\s*\(?\s*(\d+)\s*\)?|\blimit\s+(\d+)\b|\bfetch\s+first\s+(\d+)\s+rows?\s+only\b)',
  );
  static final RegExp _countAggregate = RegExp(
    r'^select\s+count\s*\(\s*(?:distinct\s+)?(?:\*|\w+)\s*\)',
  );
  static final RegExp _existsPredicate = RegExp(
    r'^select\s+exists\s*\(',
  );

  bool get _adaptivePoolingEnabled => _featureFlags?.enableOdbcExperimentalDriverAdaptivePooling ?? false;

  /// Whether a single-statement query may use native-compatible acquire.
  bool shouldUseAcquire({
    required DatabaseType databaseType,
    required QueryRequest request,
    required OdbcPreparedQueryExecution preparedExecution,
    required ConnectionAcquireOptions? acquireOptions,
    required Duration? timeout,
    Duration? defaultQueryTimeout,
    String? connectionString,
  }) {
    if (!_adaptivePoolingEnabled) {
      return false;
    }
    if (acquireOptions != null || request.expectMultipleResults) {
      return false;
    }
    if (_hasNamedParameters(preparedExecution) &&
        !_isSafeParameterizedNativeSelect(databaseType, preparedExecution)) {
      return false;
    }
    if (timeout != null &&
        !_isNativeCompatibleTimeout(
          timeout: timeout,
          defaultQueryTimeout: defaultQueryTimeout,
          connectionString: connectionString,
        )) {
      return false;
    }
    final isSafeResultShape =
        request.pagination != null ||
        isProbeQuery(preparedExecution.sql) ||
        isExplicitlyLimitedSelect(preparedExecution.sql) ||
        isBoundedAggregateQuery(preparedExecution.sql) ||
        isExistsQuery(preparedExecution.sql) ||
        _isBalancedServerBoundedSelect(databaseType, preparedExecution.sql) ||
        _isHighThroughputSqlServerSelect(databaseType, preparedExecution.sql) ||
        _isAllowlistedSql(preparedExecution.sql);
    if (!isSafeResultShape) {
      return false;
    }
    return _isNativeEligibleDialect(databaseType);
  }

  /// Whether a homogeneous read-only parallel batch may use native-compatible
  /// worker pool acquire instead of the default lease-pooled path.
  bool shouldUseReadOnlyBatchParallel({
    required DatabaseType databaseType,
    required List<SqlCommand> commands,
    required Duration? timeout,
    String? connectionString,
  }) {
    if (!ConnectionConstants.readOnlyBatchNativePoolEnabled) {
      return false;
    }
    if (!_adaptivePoolingEnabled || commands.isEmpty) {
      return false;
    }
    if (!_isNativeEligibleDialect(databaseType)) {
      return false;
    }
    for (final command in commands) {
      if (command.params != null &&
          command.params!.isNotEmpty &&
          !_isSafeParameterizedNativeSelect(
            databaseType,
            OdbcPreparedQueryExecution(sql: command.sql, parameters: command.params),
          )) {
        return false;
      }
    }
    if (timeout != null &&
        !_isNativeCompatibleTimeout(
          timeout: timeout,
          defaultQueryTimeout: ConnectionConstants.defaultQueryTimeout,
          connectionString: connectionString,
        )) {
      return false;
    }
    return true;
  }

  /// Whether a transactional batch may use the native-compatible pool path.
  bool shouldUseTransactionalBatch({
    required DatabaseType databaseType,
    required List<SqlCommand> commands,
  }) {
    if (!_adaptivePoolingEnabled || commands.isEmpty) {
      return false;
    }
    if (!commands.every((command) => isTransactionalDml(command.sql))) {
      return false;
    }
    return _isNativeEligibleDialect(databaseType);
  }

  static bool _isNativeEligibleDialect(DatabaseType databaseType) {
    return switch (databaseType) {
      DatabaseType.sqlServer || DatabaseType.postgresql => true,
      DatabaseType.sybaseAnywhere => false,
    };
  }

  static bool _hasNamedParameters(OdbcPreparedQueryExecution preparedExecution) {
    return preparedExecution.parameters?.isNotEmpty ?? false;
  }

  static bool _isSafeParameterizedNativeSelect(
    DatabaseType databaseType,
    OdbcPreparedQueryExecution preparedExecution,
  ) {
    if (!_isNativeEligibleDialect(databaseType)) {
      return false;
    }
    final sql = preparedExecution.sql;
    return isProbeQuery(sql) ||
        isExplicitlyLimitedSelect(sql) ||
        isBoundedAggregateQuery(sql) ||
        isExistsQuery(sql) ||
        _isBalancedServerBoundedSelect(databaseType, sql);
  }

  static bool _isBalancedServerBoundedSelect(DatabaseType databaseType, String sql) {
    if (!_isNativeEligibleDialect(databaseType)) {
      return false;
    }
    final normalized = normalizeSql(sql);
    if (!normalized.startsWith('select ') && !normalized.startsWith('with ')) {
      return false;
    }
    if (hasWildcardProjection(normalized)) {
      return false;
    }
    final limit = _extractExplicitRowLimit(normalized);
    return limit != null && limit <= 1000;
  }

  static bool isTransactionalDml(String sql) {
    final normalized = normalizeSql(sql);
    final startsWithSupportedDml =
        normalized.startsWith('insert ') ||
        normalized.startsWith('update ') ||
        normalized.startsWith('delete ') ||
        normalized.startsWith('merge ');
    if (!startsWithSupportedDml) {
      return false;
    }

    final padded = ' $normalized ';
    return !padded.contains(' output ') && !padded.contains(' returning ');
  }

  bool _isHighThroughputSqlServerSelect(DatabaseType databaseType, String sql) {
    if (databaseType != DatabaseType.sqlServer) {
      return false;
    }
    if (resolveOdbcUsageProfile() != OdbcUsageProfile.highThroughput) {
      return false;
    }
    final normalized = normalizeSql(sql);
    if (!normalized.startsWith('select ') && !normalized.startsWith('with ')) {
      return false;
    }
    if (hasWildcardProjection(normalized)) {
      return false;
    }
    final limit = _extractExplicitRowLimit(normalized);
    return limit == null || limit <= 1000;
  }

  static bool isProbeQuery(String sql) {
    return _probeQuery.hasMatch(normalizeSql(sql));
  }

  void rememberNativeCompatibleTimeout({
    required String connectionString,
    required Duration timeout,
  }) {
    _dsnTimeoutCache.remember(
      connectionString: connectionString,
      timeout: timeout,
    );
  }

  bool _isNativeCompatibleTimeout({
    required Duration timeout,
    required Duration? defaultQueryTimeout,
    required String? connectionString,
  }) {
    if (defaultQueryTimeout == null && connectionString == null) {
      return false;
    }
    return _dsnTimeoutCache.isCompatible(
      connectionString: connectionString ?? '',
      timeout: timeout,
      defaultQueryTimeout: defaultQueryTimeout ?? timeout,
    );
  }

  static bool isBoundedAggregateQuery(String sql) {
    return _countAggregate.hasMatch(normalizeSql(sql));
  }

  static bool isExistsQuery(String sql) {
    return _existsPredicate.hasMatch(normalizeSql(sql));
  }

  static bool isExplicitlyLimitedSelect(String sql) {
    final normalized = normalizeSql(sql);
    if (!normalized.startsWith('select ') && !normalized.startsWith('with ')) {
      return false;
    }
    if (hasWildcardProjection(normalized)) {
      return false;
    }
    final limit = _extractExplicitRowLimit(normalized);
    return limit != null && limit <= 100;
  }

  static bool hasWildcardProjection(String normalizedSql) {
    return _wildcardProjection.hasMatch('$normalizedSql ');
  }

  static int? _extractExplicitRowLimit(String normalizedSql) {
    final match = _explicitRowLimit.firstMatch(normalizedSql);
    if (match == null) {
      return null;
    }
    for (var i = 1; i <= match.groupCount; i++) {
      final value = match.group(i);
      if (value != null) {
        return int.tryParse(value);
      }
    }
    return null;
  }

  bool _isAllowlistedSql(String sql) {
    final allowlist = _resolveAllowlist();
    if (allowlist.isEmpty) {
      return false;
    }
    final normalizedSql = normalizeSql(sql);
    if (hasWildcardProjection(normalizedSql)) {
      return false;
    }
    return allowlist.contains(normalizedSql);
  }

  Set<String> _resolveAllowlist() {
    final now = DateTime.now();
    final expiresAt = _cachedAllowlistExpiresAt;
    final rawAllowlist = AppEnvironment.get(_allowlistEnvName);
    if (expiresAt != null && now.isBefore(expiresAt) && rawAllowlist == _cachedAllowlistRaw) {
      return _cachedAllowlist;
    }

    _cachedAllowlistRaw = rawAllowlist;
    _cachedAllowlistExpiresAt = now.add(_allowlistCacheTtl);
    if (rawAllowlist == null || rawAllowlist.trim().isEmpty) {
      return _cachedAllowlist = const <String>{};
    }

    return _cachedAllowlist = rawAllowlist.split('|').map(normalizeSql).where((value) => value.isNotEmpty).toSet();
  }

  static String normalizeSql(String sql) {
    return SqlValidator.removeComments(
      sql,
    ).replaceAll(_whitespaceRun, ' ').trim().replaceFirst(_trailingSemicolons, '').toLowerCase();
  }
}
