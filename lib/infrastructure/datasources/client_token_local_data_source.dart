import 'dart:convert';
import 'dart:developer' as developer;

import 'package:drift/drift.dart';
import 'package:plug_agente/core/utils/client_token_storage.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

class ClientTokenLocalDataSource {
  ClientTokenLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<ClientTokenSummary>> listTokens({
    ClientTokenListQuery? query,
  }) async {
    final effectiveQuery = query ?? const ClientTokenListQuery();
    final statement = _database.select(_database.clientTokenCacheTable);

    final normalizedClientFilter = effectiveQuery.clientIdContains.trim();
    if (normalizedClientFilter.isNotEmpty) {
      final escaped = normalizedClientFilter.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
      statement.where(
        (table) =>
            table.clientId.like('%$escaped%', escapeChar: r'\') | table.name.like('%$escaped%', escapeChar: r'\'),
      );
    }

    if (effectiveQuery.status == ClientTokenStatusFilter.active) {
      statement.where((table) => table.isRevoked.equals(false));
    } else if (effectiveQuery.status == ClientTokenStatusFilter.revoked) {
      statement.where((table) => table.isRevoked.equals(true));
    }

    statement.orderBy([
      switch (effectiveQuery.sort) {
        ClientTokenSortOption.newest => (table) => OrderingTerm(
          expression: table.createdAt,
          mode: OrderingMode.desc,
        ),
        ClientTokenSortOption.oldest => (table) => OrderingTerm(
          expression: table.createdAt,
        ),
        ClientTokenSortOption.clientAsc => (table) => OrderingTerm(
          expression: table.clientId.lower(),
        ),
        ClientTokenSortOption.clientDesc => (table) => OrderingTerm(
          expression: table.clientId.lower(),
          mode: OrderingMode.desc,
        ),
      },
      (table) => OrderingTerm(
        expression: table.createdAt,
        mode: OrderingMode.desc,
      ),
    ]);

    if (effectiveQuery.hasPagination) {
      statement.limit(effectiveQuery.pageSize!, offset: effectiveQuery.offset);
    }

    final rows = await statement.get();
    return rows.map(mapRowToSummaryWithoutTokenValue).toList();
  }

  Future<ClientTokenCacheData?> findRowById(String tokenId) {
    return (_database.select(_database.clientTokenCacheTable)
          ..where((table) => table.id.equals(tokenId))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<ClientTokenCacheData?> findRowByHash(String tokenHash) {
    return (_database.select(_database.clientTokenCacheTable)
          ..where((table) => table.tokenHash.equals(tokenHash))
          ..limit(1))
        .getSingleOrNull();
  }

  Future<void> insertToken({
    required ClientTokenSummary summary,
    required String tokenHash,
    required String? persistedTokenValue,
    required DateTime syncedAt,
  }) {
    return _database
        .into(_database.clientTokenCacheTable)
        .insertOnConflictUpdate(
          _toCompanion(
            summary,
            syncedAt: syncedAt,
            tokenHash: tokenHash,
            persistedTokenValue: persistedTokenValue,
          ),
        );
  }

  Future<void> replaceTokenRows({
    required List<({
      ClientTokenSummary summary,
      String tokenHash,
      String? persistedTokenValue,
    })> rows,
  }) async {
    if (rows.isEmpty) {
      return;
    }

    await _database.transaction(() async {
      final now = DateTime.now().toUtc();
      for (final row in rows) {
        await _database
            .into(_database.clientTokenCacheTable)
            .insertOnConflictUpdate(
              _toCompanion(
                row.summary,
                syncedAt: now,
                tokenHash: row.tokenHash,
                persistedTokenValue: row.persistedTokenValue,
              ),
            );
      }
    });
  }

  Future<Map<String, ClientTokenCacheData>> loadAllRowsById() async {
    final rows = await _database.select(_database.clientTokenCacheTable).get();
    return {for (final row in rows) row.id: row};
  }

  Future<int> applyTokenUpdate({
    required String tokenId,
    required int expectedVersion,
    required ClientTokenCacheTableCompanion companion,
  }) {
    return (_database.update(_database.clientTokenCacheTable)..where(
          (table) => table.id.equals(tokenId) & table.version.equals(expectedVersion),
        ))
        .write(companion);
  }

  Future<bool> markTokenRevoked(String tokenId) async {
    final current = await findRowById(tokenId);
    if (current == null) {
      return false;
    }
    final now = DateTime.now().toUtc();
    final affectedRows = await applyTokenUpdate(
      tokenId: tokenId,
      expectedVersion: current.version,
      companion: ClientTokenCacheTableCompanion(
        isRevoked: const Value(true),
        version: Value(current.version + 1),
        updatedAt: Value(now),
        syncedAt: Value(now),
      ),
    );
    return affectedRows > 0;
  }

  Future<ClientTokenCacheData?> deleteToken(String tokenId) async {
    final current = await findRowById(tokenId);
    final affectedRows = await (_database.delete(
      _database.clientTokenCacheTable,
    )..where((table) => table.id.equals(tokenId))).go();
    if (affectedRows > 0) {
      return current;
    }
    return null;
  }

  Future<void> updatePersistedTokenValue({
    required String tokenId,
    required String? tokenValue,
  }) {
    return (_database.update(_database.clientTokenCacheTable)..where((table) => table.id.equals(tokenId))).write(
      ClientTokenCacheTableCompanion(
        tokenValue: Value(tokenValue),
      ),
    );
  }

  ClientTokenSummary mapRowToSummaryWithoutTokenValue(ClientTokenCacheData row) {
    return ClientTokenSummary(
      id: row.id,
      clientId: row.clientId,
      name: row.name,
      createdAt: row.createdAt,
      isRevoked: row.isRevoked,
      agentId: row.agentId,
      version: row.version,
      updatedAt: row.updatedAt,
      payload: _decodePayload(row.payloadJson),
      allTables: row.allTables,
      allViews: row.allViews,
      globalPermissions: _decodeGlobalPermissions(
        row.globalPermissionsJson,
        legacyAllPermissions: row.allPermissions,
        legacyAllTables: row.allTables,
        legacyAllViews: row.allViews,
      ),
      rules: _decodeRules(row.rulesJson),
    );
  }

  ClientTokenCacheTableCompanion _toCompanion(
    ClientTokenSummary token, {
    required DateTime syncedAt,
    required String tokenHash,
    String? persistedTokenValue,
  }) {
    return ClientTokenCacheTableCompanion.insert(
      id: token.id,
      clientId: token.clientId,
      name: Value(token.name),
      isRevoked: Value(token.isRevoked),
      agentId: Value(normalizeClientTokenAgentId(token.agentId)),
      tokenValue: Value(persistedTokenValue),
      createdAt: token.createdAt.toUtc(),
      updatedAt: Value(token.updatedAt),
      version: Value(token.version),
      payloadJson: Value(jsonEncode(token.payload)),
      allTables: Value(token.allTables),
      allViews: Value(token.allViews),
      allPermissions: Value(token.allPermissions),
      globalPermissionsJson: Value(jsonEncode(token.globalPermissions.toJson())),
      rulesJson: Value(
        jsonEncode(token.rules.map((rule) => rule.toJson()).toList()),
      ),
      syncedAt: syncedAt,
      tokenHash: Value(tokenHash),
    );
  }

  Map<String, dynamic> _decodePayload(String payloadJson) {
    try {
      final decoded = jsonDecode(payloadJson);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      return const <String, dynamic>{};
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Invalid payload JSON in token cache',
        name: 'client_token_local_data_source',
        error: error,
        stackTrace: stackTrace,
      );
      return const <String, dynamic>{};
    }
  }

  List<ClientTokenRule> _decodeRules(String rulesJson) {
    try {
      final decoded = jsonDecode(rulesJson);
      if (decoded is! List<dynamic>) {
        return const <ClientTokenRule>[];
      }

      return decoded.whereType<Map<String, dynamic>>().map(ClientTokenRule.fromJson).toList();
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Invalid rules JSON in token cache',
        name: 'client_token_local_data_source',
        error: error,
        stackTrace: stackTrace,
      );
      return const <ClientTokenRule>[];
    }
  }

  ClientPermissionSet _decodeGlobalPermissions(
    String globalPermissionsJson, {
    required bool legacyAllPermissions,
    required bool legacyAllTables,
    required bool legacyAllViews,
  }) {
    try {
      final decoded = jsonDecode(globalPermissionsJson);
      if (decoded is Map<String, dynamic>) {
        return ClientPermissionSet.fromJson(decoded);
      }
      if (decoded is Map<dynamic, dynamic>) {
        return ClientPermissionSet.fromJson(
          Map<String, dynamic>.from(decoded),
        );
      }
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'Invalid global permissions JSON in token cache',
        name: 'client_token_local_data_source',
        error: error,
        stackTrace: stackTrace,
      );
    }

    if (legacyAllPermissions) {
      return ClientPermissionSet.fullAccess;
    }
    if (legacyAllTables || legacyAllViews) {
      return ClientPermissionSet.legacyScopedAccess;
    }
    return ClientPermissionSet.none;
  }
}
