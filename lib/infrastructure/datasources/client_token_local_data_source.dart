import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/core/utils/client_token_storage.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_page.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_runtime_restrictions.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

class ClientTokenLocalDataSource {
  ClientTokenLocalDataSource(this._database);

  final AppDatabase _database;

  Future<List<ClientTokenSummary>> listTokens({
    ClientTokenListQuery? query,
  }) => _listTokens(query: query ?? const ClientTokenListQuery());

  Future<List<ClientTokenSummary>> _listTokens({
    required ClientTokenListQuery query,
    bool allowPolicyRecovery = false,
  }) async {
    final effectiveQuery = query;
    final statement = _database.select(_database.clientTokenCacheTable);

    statement.where((table) => _filter(table, effectiveQuery));

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
      if (effectiveQuery.sort == ClientTokenSortOption.clientAsc ||
          effectiveQuery.sort == ClientTokenSortOption.clientDesc)
        (table) => OrderingTerm(
          expression: table.createdAt,
          mode: OrderingMode.desc,
        ),
      (table) => OrderingTerm(expression: table.id),
    ]);

    if (effectiveQuery.hasPagination) {
      statement.limit(effectiveQuery.pageSize!, offset: effectiveQuery.offset);
    }

    final rows = await statement.get();
    return rows.map(allowPolicyRecovery ? _mapRowForAdministration : mapRowToSummaryWithoutTokenValue).toList();
  }

  Expression<bool> _filter($ClientTokenCacheTableTable table, ClientTokenListQuery query) {
    Expression<bool> filter = const Constant(true);
    final value = query.clientIdContains.trim();
    if (value.isNotEmpty) {
      final escaped = value.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');
      filter = table.clientId.like('%$escaped%', escapeChar: r'\') | table.name.like('%$escaped%', escapeChar: r'\');
    }
    return switch (query.status) {
      ClientTokenStatusFilter.all => filter,
      ClientTokenStatusFilter.active => filter & table.isRevoked.equals(false),
      ClientTokenStatusFilter.revoked => filter & table.isRevoked.equals(true),
    };
  }

  Future<int> _count(ClientTokenListQuery query) async {
    final table = _database.clientTokenCacheTable;
    final count = table.id.count();
    final statement = _database.selectOnly(table)
      ..addColumns([count])
      ..where(_filter(table, query));
    return (await statement.getSingle()).read(count)!;
  }

  Future<int> countActiveTokens() => _count(const ClientTokenListQuery(status: ClientTokenStatusFilter.active));

  Future<ClientTokenPage> listTokenPage({required ClientTokenListQuery query}) {
    return _database.transaction(() async {
      final total = await _count(query);
      final size = query.pageSize ?? ClientTokenListQuery.defaultPageSize;
      final lastPage = total == 0 ? 1 : (total / size).ceil();
      final page = (query.page ?? 1).clamp(1, lastPage);
      final items = await _listTokens(
        query: query.copyWith(page: page, pageSize: size),
        allowPolicyRecovery: true,
      );
      return ClientTokenPage(items: items, page: page, pageSize: size, totalCount: total);
    });
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
    required List<
      ({
        ClientTokenSummary summary,
        String tokenHash,
        String? persistedTokenValue,
      })
    >
    rows,
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

  Future<bool> markTokenRevoked(String tokenId) async => await revokeTokenRow(tokenId) != null;

  Future<ClientTokenCacheData?> revokeTokenRow(String tokenId) {
    return _database.transaction(() async {
      final current = await findRowById(tokenId);
      if (current == null || current.isRevoked) return current;
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
      return affectedRows > 0 ? current : null;
    });
  }

  Future<ClientTokenCacheData?> deleteToken(String tokenId) {
    return _database.transaction(() async {
      final current = await findRowById(tokenId);
      if (current == null) return null;
      final affectedRows = await (_database.delete(
        _database.clientTokenCacheTable,
      )..where((table) => table.id.equals(tokenId) & table.version.equals(current.version))).go();
      return affectedRows > 0 ? current : null;
    });
  }

  Future<int> updatePersistedTokenValue({
    required String tokenId,
    required String? tokenValue,
    required String expectedTokenHash,
    required int expectedVersion,
  }) {
    return (_database.update(_database.clientTokenCacheTable)..where(
          (table) =>
              table.id.equals(tokenId) &
              table.tokenHash.equals(expectedTokenHash) &
              table.version.equals(expectedVersion),
        ))
        .write(ClientTokenCacheTableCompanion(tokenValue: Value(tokenValue)));
  }

  Future<void> runIfTokenHashUnreferenced(String tokenHash, Future<void> Function() action) {
    return _database.transaction(() async {
      if (await findRowByHash(tokenHash) == null) await action();
    });
  }

  ClientTokenSummary mapRowToSummaryWithoutTokenValue(ClientTokenCacheData row) {
    try {
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
        globalPermissions: _decodeGlobalPermissions(row.globalPermissionsJson),
        rules: _decodeRules(row.rulesJson),
      );
    } on FormatException {
      throw domain.ConfigurationFailure.withContext(
        message:
            'A política salva deste token está inválida. Revogue-o e crie outro token com as permissões desejadas.',
        code: 'CLIENT_TOKEN_POLICY_INVALID',
        context: {
          'operation': 'decode_client_token_policy',
          'token_id': row.id,
          'reason': AuthorizationContextConstants.invalidPolicyReason,
          'user_message': 'Política de token inválida. Revogue o token e crie outro para recuperar o acesso.',
        },
      );
    }
  }

  ClientTokenSummary _mapRowForAdministration(ClientTokenCacheData row) {
    try {
      return mapRowToSummaryWithoutTokenValue(row);
    } on domain.ConfigurationFailure catch (failure) {
      if (failure.code != 'CLIENT_TOKEN_POLICY_INVALID') rethrow;
      failure.log();
      return ClientTokenSummary(
        id: row.id,
        clientId: row.clientId,
        name: row.name,
        createdAt: row.createdAt,
        isRevoked: row.isRevoked,
        agentId: row.agentId,
        version: row.version,
        updatedAt: row.updatedAt,
        allTables: false,
        allViews: false,
        globalPermissions: ClientPermissionSet.none,
        rules: const [],
        hasInvalidPolicy: true,
      );
    }
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

  Object? _decodeJson(String value) {
    try {
      return jsonDecode(value);
    } on FormatException {
      // Never attach the persisted JSON to exceptions or logs.
      throw const FormatException('Invalid token policy JSON');
    }
  }

  Map<String, dynamic> _decodePayload(String payloadJson) {
    final decoded = _decodeJson(payloadJson);
    if (decoded is! Map<String, dynamic> || !ClientTokenRuntimeRestrictions.isValidPayload(decoded)) {
      throw const FormatException('Invalid token payload');
    }
    return decoded;
  }

  List<ClientTokenRule> _decodeRules(String rulesJson) {
    final decoded = _decodeJson(rulesJson);
    if (decoded is! List || decoded.any((rule) => rule is! Map<String, dynamic>)) {
      throw const FormatException('Invalid token rules');
    }
    return decoded.cast<Map<String, dynamic>>().map(ClientTokenRule.fromJson).toList();
  }

  ClientPermissionSet _decodeGlobalPermissions(String globalPermissionsJson) {
    final decoded = _decodeJson(globalPermissionsJson);
    if (decoded is! Map<String, dynamic>) throw const FormatException('Invalid token permissions');
    return ClientPermissionSet.fromJson(decoded);
  }
}
