import 'package:plug_agente/application/rpc/sql_rpc_negotiated_capabilities.dart';
import 'package:plug_agente/core/config/app_environment.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/value_objects/database_driver.dart';

enum DbStreamingAutoReason {
  none,
  prefer,
  largeMaxRows,
  sqlLength,
  allowlist,
  sqlSignal,
}

class SqlDbStreamingAutoPolicy {
  SqlDbStreamingAutoPolicy({
    String? Function(String key)? envGetter,
    Duration allowlistCacheTtl = const Duration(seconds: 10),
    int sqlLengthThreshold = 240,
    DateTime Function()? clock,
  }) : _envGetter = envGetter ?? AppEnvironment.get,
       _allowlistCacheTtl = allowlistCacheTtl,
       _sqlLengthThreshold = sqlLengthThreshold,
       _clock = clock ?? DateTime.now;

  static const String allowlistEnvKey = 'DB_STREAMING_AUTO_TABLE_ALLOWLIST';

  static const List<String> largeSqlSignals = <String>[
    ' join ',
    ' union ',
    ' group by ',
    ' order by ',
  ];

  final String? Function(String key) _envGetter;
  final Duration _allowlistCacheTtl;
  final int _sqlLengthThreshold;
  final DateTime Function() _clock;

  String? _cachedTableAllowlistRaw;
  Set<String> _cachedTableAllowlist = const <String>{};
  DateTime? _cachedTableAllowlistExpiresAt;

  DbStreamingAutoReason resolveAutoReason({
    required FeatureFlags featureFlags,
    required QueryRequest queryRequest,
    required String sql,
    required Map<String, dynamic> negotiatedExtensions,
    required bool preferDbStreaming,
    int? effectiveMaxRows,
    TransportLimits limits = const TransportLimits(),
  }) {
    if (!featureFlags.enableSocketStreamingFromDb ||
        featureFlags.enableSocketStreamingChunks ||
        !supportsStreamingChunks(negotiatedExtensions) ||
        queryRequest.pagination != null ||
        queryRequest.expectMultipleResults ||
        (queryRequest.parameters?.isNotEmpty ?? false)) {
      return DbStreamingAutoReason.none;
    }

    final normalized = normalizeSqlForDbStreaming(sql);
    if (!normalized.startsWith(' select ') && !normalized.startsWith(' with ')) {
      return DbStreamingAutoReason.none;
    }
    if (containsExplicitRowLimit(normalized)) {
      return DbStreamingAutoReason.none;
    }
    if (preferDbStreaming) {
      return DbStreamingAutoReason.prefer;
    }
    if (requiresExplicitDbStreamingPreference(normalized)) {
      return DbStreamingAutoReason.none;
    }
    if (normalized.length >= _sqlLengthThreshold) {
      return DbStreamingAutoReason.sqlLength;
    }
    if (matchesTableAllowlist(normalized)) {
      return DbStreamingAutoReason.allowlist;
    }
    if (effectiveMaxRows != null &&
        effectiveMaxRows >= limits.streamingRowThreshold) {
      return DbStreamingAutoReason.largeMaxRows;
    }
    if (largeSqlSignals.any(normalized.contains)) {
      return DbStreamingAutoReason.sqlSignal;
    }
    return DbStreamingAutoReason.none;
  }

  bool shouldMaterializeBoundedDbStreaming(
    String normalizedSql, {
    required int effectiveMaxRows,
    required TransportLimits limits,
  }) {
    if (containsExplicitRowLimit(normalizedSql)) {
      final explicitLimit = parseExplicitRowLimit(normalizedSql);
      if (explicitLimit != null && explicitLimit >= limits.streamingRowThreshold) {
        return false;
      }
      return true;
    }
    return effectiveMaxRows < limits.streamingRowThreshold;
  }

  int? parseExplicitRowLimit(String normalizedSql) {
    final topMatch = RegExp(r'\btop\s+(\d+)\b', caseSensitive: false).firstMatch(normalizedSql);
    if (topMatch != null) {
      return int.tryParse(topMatch.group(1)!);
    }
    final limitMatch = RegExp(r'\blimit\s+(\d+)\b', caseSensitive: false).firstMatch(normalizedSql);
    if (limitMatch != null) {
      return int.tryParse(limitMatch.group(1)!);
    }
    final fetchMatch = RegExp(r'\bfetch\s+first\s+(\d+)\b', caseSensitive: false).firstMatch(normalizedSql);
    if (fetchMatch != null) {
      return int.tryParse(fetchMatch.group(1)!);
    }
    return null;
  }

  bool isDriverAllowed(String driverName) {
    return switch (DatabaseDriver.fromString(driverName)) {
      DatabaseDriver.sqlServer => true,
      DatabaseDriver.postgreSQL => true,
      DatabaseDriver.sqlAnywhere => true,
      DatabaseDriver.unknown => false,
    };
  }

  bool matchesTableAllowlist(String normalizedSql) {
    final allowlist = tableAllowlist();
    if (allowlist.isEmpty) {
      return false;
    }
    if (allowlist.contains('*')) {
      return true;
    }

    final tableName = firstTableName(normalizedSql);
    return tableName != null && allowlist.contains(tableName);
  }

  bool requiresExplicitDbStreamingPreference(String normalizedSql) {
    return normalizedSql.startsWith(' with ') ||
        normalizedSql.contains(' join ') ||
        RegExp(r'\bfrom\s*\(', caseSensitive: false).hasMatch(normalizedSql);
  }

  Set<String> tableAllowlist() {
    final now = _clock();
    final expiresAt = _cachedTableAllowlistExpiresAt;
    final rawAllowlist = _envGetter(allowlistEnvKey);
    if (expiresAt != null && now.isBefore(expiresAt) && rawAllowlist == _cachedTableAllowlistRaw) {
      return _cachedTableAllowlist;
    }

    _cachedTableAllowlistRaw = rawAllowlist;
    _cachedTableAllowlistExpiresAt = now.add(_allowlistCacheTtl);
    if (rawAllowlist == null) {
      return _cachedTableAllowlist = const <String>{};
    }

    return _cachedTableAllowlist = rawAllowlist
        .split(',')
        .map(normalizeTableName)
        .where((value) => value.isNotEmpty)
        .toSet();
  }

  String? firstTableName(String normalizedSql) {
    final match = RegExp(r'\bfrom\s+([a-z0-9_\.\[\]"]+)', caseSensitive: false).firstMatch(normalizedSql);
    final table = match?.group(1);
    if (table == null) {
      return null;
    }
    return normalizeTableName(table);
  }

  String normalizeTableName(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'^[\["]+|[\]"]+$'), '').replaceAll(RegExp(r'[\[\]"]'), '');
  }

  String normalizeSqlForDbStreaming(String sql) {
    return ' ${sql.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim()} ';
  }

  bool containsExplicitRowLimit(String normalizedSql) {
    return RegExp(r'\btop\b', caseSensitive: false).hasMatch(normalizedSql) ||
        normalizedSql.contains(' limit ') ||
        normalizedSql.contains(' fetch first ') ||
        normalizedSql.contains(' offset ') ||
        RegExp(r'\brownum\s*<=', caseSensitive: false).hasMatch(normalizedSql);
  }
}
