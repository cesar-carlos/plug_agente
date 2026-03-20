import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/entities/client_token_update_result.dart';
import 'package:plug_agente/domain/repositories/i_token_secret_store.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

class ClientTokenVersionConflictException implements Exception {
  const ClientTokenVersionConflictException({required this.currentVersion});

  final int currentVersion;

  @override
  String toString() =>
      'ClientTokenVersionConflictException(currentVersion: $currentVersion)';
}

class ClientTokenLocalDataSource {
  ClientTokenLocalDataSource(this._database, {ITokenSecretStore? secretStore})
    : _secretStore = secretStore;

  final AppDatabase _database;
  final ITokenSecretStore? _secretStore;
  final Random _random = Random.secure();
  static const _secureStorageMarker = '__secure_storage__';

  Future<String> createToken(ClientTokenCreateRequest request) async {
    final now = DateTime.now().toUtc();
    final tokenId = _buildTokenId();
    final opaqueToken = _generateOpaqueToken();
    final tokenHash = _hashToken(opaqueToken);
    await _saveSecretBestEffort(tokenId, opaqueToken);
    final summary = ClientTokenSummary(
      id: tokenId,
      clientId: request.clientId.trim(),
      createdAt: now,
      isRevoked: false,
      tokenValue: opaqueToken,
      allTables: request.allTables,
      allViews: request.allViews,
      allPermissions: request.allPermissions,
      rules: request.rules,
      agentId: request.agentId?.trim().isEmpty ?? true ? null : request.agentId,
      payload: request.payload,
    );

    await _database
        .into(_database.clientTokenCacheTable)
        .insertOnConflictUpdate(
          _toCompanion(summary, syncedAt: now, tokenHash: tokenHash),
        );

    return opaqueToken;
  }

  Future<void> replaceTokens(List<ClientTokenSummary> tokens) async {
    await _database.transaction(() async {
      await _database.delete(_database.clientTokenCacheTable).go();

      if (tokens.isEmpty) {
        return;
      }

      final now = DateTime.now().toUtc();
      final companions = tokens
          .map((token) => _toCompanion(token, syncedAt: now))
          .toList();

      await _database.batch((batch) {
        batch.insertAll(_database.clientTokenCacheTable, companions);
      });
    });
  }

  Future<List<ClientTokenSummary>> listTokens({
    ClientTokenListQuery? query,
  }) async {
    final effectiveQuery = query ?? const ClientTokenListQuery();
    final statement = _database.select(_database.clientTokenCacheTable);

    final normalizedClientFilter = effectiveQuery.clientIdContains.trim();
    if (normalizedClientFilter.isNotEmpty) {
      statement.where(
        (table) => table.clientId.like('%$normalizedClientFilter%'),
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

    final tokens = <ClientTokenSummary>[];
    for (final row in rows) {
      tokens.add(await _toEntity(row));
    }
    return tokens;
  }

  Future<ClientTokenSummary?> getTokenById(String tokenId) async {
    final row =
        await (_database.select(_database.clientTokenCacheTable)
              ..where((table) => table.id.equals(tokenId))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _toEntity(row);
  }

  Future<ClientTokenSummary?> getTokenByHash(String tokenHash) async {
    final row =
        await (_database.select(_database.clientTokenCacheTable)
              ..where((table) => table.tokenHash.equals(tokenHash))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _toEntity(row);
  }

  String hashTokenForLookup(String token) {
    return _hashToken(token);
  }

  Future<bool> markTokenRevoked(String tokenId) async {
    final current =
        await (_database.select(_database.clientTokenCacheTable)
              ..where((table) => table.id.equals(tokenId))
              ..limit(1))
            .getSingleOrNull();
    if (current == null) {
      return false;
    }
    final now = DateTime.now().toUtc();
    final affectedRows =
        await (_database.update(
              _database.clientTokenCacheTable,
            )..where(
              (table) =>
                  table.id.equals(tokenId) &
                  table.version.equals(current.version),
            ))
            .write(
              ClientTokenCacheTableCompanion(
                isRevoked: const Value(true),
                version: Value(current.version + 1),
                updatedAt: Value(now),
                syncedAt: Value(now),
              ),
            );
    return affectedRows > 0;
  }

  Future<ClientTokenUpdateResult?> updateToken(
    String tokenId,
    ClientTokenCreateRequest request, {
    int? expectedVersion,
  }) async {
    final current =
        await (_database.select(_database.clientTokenCacheTable)
              ..where((table) => table.id.equals(tokenId))
              ..limit(1))
            .getSingleOrNull();
    if (current == null) {
      return null;
    }

    if (expectedVersion != null && current.version != expectedVersion) {
      throw ClientTokenVersionConflictException(
        currentVersion: current.version,
      );
    }

    final newTokenValue = _generateOpaqueToken();
    final newTokenHash = _hashToken(newTokenValue);
    await _saveSecretBestEffort(tokenId, newTokenValue);
    final nextVersion = current.version + 1;
    final now = DateTime.now().toUtc();

    final affectedRows =
        await (_database.update(
              _database.clientTokenCacheTable,
            )..where(
              (table) =>
                  table.id.equals(tokenId) &
                  table.version.equals(current.version),
            ))
            .write(
              ClientTokenCacheTableCompanion(
                clientId: Value(request.clientId.trim()),
                agentId: Value(
                  request.agentId?.trim().isEmpty ?? true
                      ? null
                      : request.agentId,
                ),
                tokenHash: Value(newTokenHash),
                tokenValue: Value(_persistedTokenValue(newTokenValue)),
                payloadJson: Value(jsonEncode(request.payload)),
                allTables: Value(request.allTables),
                allViews: Value(request.allViews),
                allPermissions: Value(request.allPermissions),
                rulesJson: Value(
                  jsonEncode(
                    request.rules.map((rule) => rule.toJson()).toList(),
                  ),
                ),
                version: Value(nextVersion),
                updatedAt: Value(now),
                syncedAt: Value(now),
              ),
            );
    if (affectedRows == 0) {
      final latest =
          await (_database.select(_database.clientTokenCacheTable)
                ..where((table) => table.id.equals(tokenId))
                ..limit(1))
              .getSingleOrNull();
      throw ClientTokenVersionConflictException(
        currentVersion: latest?.version ?? current.version,
      );
    }
    return ClientTokenUpdateResult(
      tokenValue: newTokenValue,
      version: nextVersion,
      updatedAt: now,
    );
  }

  Future<bool> deleteToken(String tokenId) async {
    final affectedRows = await (_database.delete(
      _database.clientTokenCacheTable,
    )..where((table) => table.id.equals(tokenId))).go();
    if (affectedRows > 0) {
      await _deleteSecretBestEffort(tokenId);
    }
    return affectedRows > 0;
  }

  ClientTokenCacheTableCompanion _toCompanion(
    ClientTokenSummary token, {
    required DateTime syncedAt,
    String? tokenHash,
  }) {
    return ClientTokenCacheTableCompanion.insert(
      id: token.id,
      clientId: token.clientId,
      isRevoked: Value(token.isRevoked),
      agentId: Value(token.agentId),
      tokenValue: Value(_persistedTokenValue(token.tokenValue)),
      createdAt: token.createdAt.toUtc(),
      updatedAt: Value(token.updatedAt),
      version: Value(token.version),
      payloadJson: Value(jsonEncode(token.payload)),
      allTables: Value(token.allTables),
      allViews: Value(token.allViews),
      allPermissions: Value(token.allPermissions),
      rulesJson: Value(
        jsonEncode(token.rules.map((rule) => rule.toJson()).toList()),
      ),
      syncedAt: syncedAt,
      tokenHash: tokenHash == null ? const Value.absent() : Value(tokenHash),
    );
  }

  Future<ClientTokenSummary> _toEntity(ClientTokenCacheData row) async {
    final tokenValue = await _resolveTokenValue(
      tokenId: row.id,
      persistedTokenValue: row.tokenValue,
    );
    return ClientTokenSummary(
      id: row.id,
      clientId: row.clientId,
      createdAt: row.createdAt,
      isRevoked: row.isRevoked,
      agentId: row.agentId,
      tokenValue: tokenValue,
      version: row.version,
      updatedAt: row.updatedAt,
      payload: _decodePayload(row.payloadJson),
      allTables: row.allTables,
      allViews: row.allViews,
      allPermissions: row.allPermissions,
      rules: _decodeRules(row.rulesJson),
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

      return decoded
          .whereType<Map<String, dynamic>>()
          .map(ClientTokenRule.fromJson)
          .toList();
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

  String _generateOpaqueToken() {
    const tokenLength = 32;
    final bytes = List<int>.generate(
      tokenLength,
      (_) => _random.nextInt(256),
    );
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  String _hashToken(String token) {
    final bytes = utf8.encode(token);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  String _buildTokenId() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    final suffix = _random.nextInt(1 << 20).toRadixString(16);
    return '${timestamp}_$suffix';
  }

  String? _persistedTokenValue(String? tokenValue) {
    if (tokenValue == null || tokenValue.isEmpty) {
      return null;
    }
    return _secretStore == null ? tokenValue : _secureStorageMarker;
  }

  Future<String?> _resolveTokenValue({
    required String tokenId,
    required String? persistedTokenValue,
  }) async {
    final secretStore = _secretStore;
    if (secretStore != null) {
      final secret = await _readSecretBestEffort(tokenId);
      if (secret != null && secret.isNotEmpty) {
        return secret;
      }
    }

    if (persistedTokenValue == null || persistedTokenValue.isEmpty) {
      return null;
    }
    if (persistedTokenValue == _secureStorageMarker) {
      return null;
    }

    // Legacy token values were persisted in plaintext before secure storage.
    await _migrateLegacyTokenValueToSecretStore(
      tokenId: tokenId,
      tokenValue: persistedTokenValue,
    );
    return persistedTokenValue;
  }

  Future<void> _migrateLegacyTokenValueToSecretStore({
    required String tokenId,
    required String tokenValue,
  }) async {
    if (_secretStore == null) {
      return;
    }
    await _saveSecretBestEffort(tokenId, tokenValue);
    try {
      await (_database.update(
        _database.clientTokenCacheTable,
      )..where((table) => table.id.equals(tokenId))).write(
        const ClientTokenCacheTableCompanion(
          tokenValue: Value(_secureStorageMarker),
        ),
      );
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Token migration to secret store failed (best effort)',
        name: 'client_token_local_data_source',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _saveSecretBestEffort(String tokenId, String tokenValue) async {
    final secretStore = _secretStore;
    if (secretStore == null) {
      return;
    }
    try {
      await secretStore.saveSecret(tokenId, tokenValue);
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Secret persistence failed (must not block token operations)',
        name: 'client_token_local_data_source',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<String?> _readSecretBestEffort(String tokenId) async {
    final secretStore = _secretStore;
    if (secretStore == null) {
      return null;
    }
    try {
      return await secretStore.readSecret(tokenId);
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Secret read failed',
        name: 'client_token_local_data_source',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> _deleteSecretBestEffort(String tokenId) async {
    final secretStore = _secretStore;
    if (secretStore == null) {
      return;
    }
    try {
      await secretStore.deleteSecret(tokenId);
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Secret delete failed (best effort cleanup)',
        name: 'client_token_local_data_source',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }
}
