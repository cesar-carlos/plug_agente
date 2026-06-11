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
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

class ClientTokenVersionConflictException implements Exception {
  const ClientTokenVersionConflictException({required this.currentVersion});

  final int currentVersion;

  @override
  String toString() => 'ClientTokenVersionConflictException(currentVersion: $currentVersion)';
}

class ClientTokenLocalDataSource {
  ClientTokenLocalDataSource(this._database, {ITokenSecretStore? secretStore}) : _secretStore = secretStore;

  final AppDatabase _database;
  final ITokenSecretStore? _secretStore;
  final Random _random = Random.secure();
  static const _secureStorageMarker = '__secure_storage__';

  Future<String> createToken(ClientTokenCreateRequest request) async {
    final now = DateTime.now().toUtc();
    final tokenId = _buildTokenId();
    final opaqueToken = _generateOpaqueToken();
    final tokenHash = _hashToken(opaqueToken);
    await _saveSecretBestEffort(tokenHash, opaqueToken);
    final summary = ClientTokenSummary(
      id: tokenId,
      clientId: request.clientId.trim(),
      name: request.name.trim(),
      createdAt: now,
      isRevoked: false,
      tokenValue: opaqueToken,
      allTables: request.allTables,
      allViews: request.allViews,
      globalPermissions: request.effectiveGlobalPermissions,
      rules: request.effectiveRules,
      agentId: _normalizeAgentId(request.agentId),
      payload: request.payload,
    );

    try {
      await _database
          .into(_database.clientTokenCacheTable)
          .insertOnConflictUpdate(
            _toCompanion(summary, syncedAt: now, tokenHash: tokenHash),
          );
    } on Exception {
      await _deleteSecretBestEffort(tokenHash);
      rethrow;
    }

    return opaqueToken;
  }

  Future<void> replaceTokens(List<ClientTokenSummary> tokens) async {
    if (tokens.isEmpty) {
      return;
    }

    final previousRowsById = {
      for (final row in await _database.select(_database.clientTokenCacheTable).get()) row.id: row,
    };

    await _database.transaction(() async {
      final now = DateTime.now().toUtc();
      for (final token in tokens) {
        await _database
            .into(_database.clientTokenCacheTable)
            .insertOnConflictUpdate(
              _toCompanion(token, syncedAt: now),
            );
      }
    });

    await _syncSecretsForReplacement(
      tokens,
      previousRowsById: previousRowsById,
    );
  }

  Future<List<ClientTokenSummary>> listTokens({
    ClientTokenListQuery? query,
  }) async {
    final effectiveQuery = query ?? const ClientTokenListQuery();
    final statement = _database.select(_database.clientTokenCacheTable);

    final normalizedClientFilter = effectiveQuery.clientIdContains.trim();
    if (normalizedClientFilter.isNotEmpty) {
      // Escape SQLite LIKE wildcards before embedding in the pattern so that
      // user input containing % or _ is treated as literal characters.
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

    return rows.map(_toEntityWithoutTokenValue).toList();
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

  Future<String?> getTokenSecret(String tokenId) async {
    final row =
        await (_database.select(_database.clientTokenCacheTable)
              ..where((table) => table.id.equals(tokenId))
              ..limit(1))
            .getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _resolveTokenValue(
      tokenId: row.id,
      tokenHash: row.tokenHash,
      persistedTokenValue: row.tokenValue,
    );
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
              (table) => table.id.equals(tokenId) & table.version.equals(current.version),
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

    final currentSummary = _toEntityWithoutTokenValue(current);
    final policyChanged = request.changesAuthorizationPolicyFrom(currentSummary);
    final metadataChanged = request.changesMetadataFrom(currentSummary);

    // Pure no-op: form was saved with the exact persisted state. Skip the DB
    // write entirely so version, updatedAt, secrets and audit trail stay
    // untouched.
    if (!policyChanged && !metadataChanged) {
      return ClientTokenUpdateResult(
        outcome: ClientTokenUpdateOutcome.unchanged,
        version: current.version,
        updatedAt: current.updatedAt ?? current.createdAt,
      );
    }

    final shouldRotateToken = policyChanged;
    final nextVersion = current.version + 1;
    final now = DateTime.now().toUtc();

    final String? newTokenValue;
    final String? newTokenHash;
    if (shouldRotateToken) {
      newTokenValue = _generateOpaqueToken();
      newTokenHash = _hashToken(newTokenValue);
      await _saveSecretBestEffort(newTokenHash, newTokenValue);
    } else {
      newTokenValue = null;
      newTokenHash = null;
    }

    try {
      // The token secret columns (tokenHash and tokenValue) are intentionally
      // left absent when the policy did not change so the existing secret
      // and its hash are preserved while still bumping version + metadata.
      final affectedRows =
          await (_database.update(
                _database.clientTokenCacheTable,
              )..where(
                (table) => table.id.equals(tokenId) & table.version.equals(current.version),
              ))
              .write(
                ClientTokenCacheTableCompanion(
                  clientId: Value(request.normalizedClientId),
                  name: Value(request.normalizedName),
                  agentId: Value(request.normalizedAgentId),
                  tokenHash: shouldRotateToken ? Value(newTokenHash!) : const Value.absent(),
                  tokenValue: shouldRotateToken ? Value(_persistedTokenValue(newTokenValue)) : const Value.absent(),
                  payloadJson: Value(jsonEncode(request.payload)),
                  allTables: Value(request.allTables),
                  allViews: Value(request.allViews),
                  allPermissions: Value(request.allPermissions),
                  globalPermissionsJson: Value(
                    jsonEncode(request.effectiveGlobalPermissions.toJson()),
                  ),
                  rulesJson: Value(
                    jsonEncode(
                      request.effectiveRules.map((rule) => rule.toJson()).toList(),
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
    } on Exception {
      if (shouldRotateToken) {
        await _deleteSecretBestEffort(newTokenHash!);
      }
      rethrow;
    }
    if (shouldRotateToken) {
      await _deleteStoredSecretsBestEffort(
        tokenId: tokenId,
        tokenHash: current.tokenHash,
      );
    }
    return ClientTokenUpdateResult(
      outcome: shouldRotateToken ? ClientTokenUpdateOutcome.rotated : ClientTokenUpdateOutcome.metadataOnly,
      tokenValue: newTokenValue,
      version: nextVersion,
      updatedAt: now,
    );
  }

  Future<bool> deleteToken(String tokenId) async {
    final current =
        await (_database.select(_database.clientTokenCacheTable)
              ..where((table) => table.id.equals(tokenId))
              ..limit(1))
            .getSingleOrNull();
    final affectedRows = await (_database.delete(
      _database.clientTokenCacheTable,
    )..where((table) => table.id.equals(tokenId))).go();
    if (affectedRows > 0 && current != null) {
      await _deleteStoredSecretsBestEffort(
        tokenId: tokenId,
        tokenHash: current.tokenHash,
      );
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
      name: Value(token.name),
      isRevoked: Value(token.isRevoked),
      agentId: Value(_normalizeAgentId(token.agentId)),
      tokenValue: Value(_persistedTokenValue(token.tokenValue)),
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
      tokenHash: Value(tokenHash ?? _fallbackStoredTokenHash(token)),
    );
  }

  Future<ClientTokenSummary> _toEntity(ClientTokenCacheData row) async {
    final tokenValue = await _resolveTokenValue(
      tokenId: row.id,
      tokenHash: row.tokenHash,
      persistedTokenValue: row.tokenValue,
    );
    return ClientTokenSummary(
      id: row.id,
      clientId: row.clientId,
      name: row.name,
      createdAt: row.createdAt,
      isRevoked: row.isRevoked,
      agentId: row.agentId,
      tokenValue: tokenValue,
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

  ClientTokenSummary _toEntityWithoutTokenValue(ClientTokenCacheData row) {
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

  String? _normalizeAgentId(String? agentId) {
    final trimmed = agentId?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  String _fallbackStoredTokenHash(ClientTokenSummary token) {
    final tokenValue = token.tokenValue?.trim();
    if (tokenValue != null && tokenValue.isNotEmpty) {
      return _hashToken(tokenValue);
    }
    return 'missing:${token.id}';
  }

  String? _persistedTokenValue(String? tokenValue) {
    if (tokenValue == null || tokenValue.isEmpty) {
      return null;
    }
    return _secureStorageEnabled ? _secureStorageMarker : tokenValue;
  }

  bool get _secureStorageEnabled => _secretStore?.isAvailable ?? false;

  Future<String?> _resolveTokenValue({
    required String tokenId,
    required String tokenHash,
    required String? persistedTokenValue,
  }) async {
    if (_secureStorageEnabled) {
      final secret = await _readSecretBestEffort(tokenHash);
      if (secret != null && secret.isNotEmpty) {
        return secret;
      }
      final legacySecret = await _readSecretBestEffort(tokenId);
      if (legacySecret != null && legacySecret.isNotEmpty) {
        await _migrateLegacyTokenValueToSecretStore(
          tokenId: tokenId,
          tokenHash: tokenHash,
          tokenValue: legacySecret,
        );
        return legacySecret;
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
      tokenHash: tokenHash,
      tokenValue: persistedTokenValue,
    );
    return persistedTokenValue;
  }

  Future<void> _migrateLegacyTokenValueToSecretStore({
    required String tokenId,
    required String tokenHash,
    required String tokenValue,
  }) async {
    if (!_secureStorageEnabled) {
      return;
    }
    final didSave = await _saveSecretBestEffort(tokenHash, tokenValue);
    if (!didSave) {
      return;
    }
    try {
      await (_database.update(
        _database.clientTokenCacheTable,
      )..where((table) => table.id.equals(tokenId))).write(
        const ClientTokenCacheTableCompanion(
          tokenValue: Value(_secureStorageMarker),
        ),
      );
      await _deleteSecretBestEffort(tokenId);
      developer.log(
        'Migrated legacy client token secret to hash-based storage (token_id=$tokenId)',
        name: 'client_token_local_data_source',
        level: 800,
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

  Future<bool> _saveSecretBestEffort(String secretKey, String tokenValue) async {
    final secretStore = _secretStore;
    if (secretStore == null || !secretStore.isAvailable) {
      return false;
    }
    try {
      await secretStore.saveSecret(secretKey, tokenValue);
      return true;
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Secret persistence failed (must not block token operations)',
        name: 'client_token_local_data_source',
        error: e,
        stackTrace: stackTrace,
      );
      return false;
    }
  }

  Future<String?> _readSecretBestEffort(String secretKey) async {
    final secretStore = _secretStore;
    if (secretStore == null) {
      return null;
    }
    try {
      return await secretStore.readSecret(secretKey);
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

  Future<void> _deleteSecretBestEffort(String secretKey) async {
    final secretStore = _secretStore;
    if (secretStore == null) {
      return;
    }
    try {
      await secretStore.deleteSecret(secretKey);
    } on Exception catch (e, stackTrace) {
      developer.log(
        'Secret delete failed (best effort cleanup)',
        name: 'client_token_local_data_source',
        error: e,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _deleteStoredSecretsBestEffort({
    required String tokenId,
    required String tokenHash,
  }) async {
    await _deleteSecretBestEffort(tokenHash);
    await _deleteSecretBestEffort(tokenId);
  }

  Future<void> _syncSecretsForReplacement(
    List<ClientTokenSummary> tokens, {
    required Map<String, ClientTokenCacheData> previousRowsById,
  }) async {
    for (final token in tokens) {
      final previousRow = previousRowsById[token.id];
      final tokenValue = token.tokenValue?.trim();
      if (tokenValue == null || tokenValue.isEmpty) {
        await _deleteStoredSecretsBestEffort(
          tokenId: token.id,
          tokenHash: _fallbackStoredTokenHash(token),
        );
        if (previousRow != null) {
          await _deleteSecretBestEffort(previousRow.tokenHash);
        }
        continue;
      }
      final tokenHash = _fallbackStoredTokenHash(token);
      await _saveSecretBestEffort(tokenHash, tokenValue);
      await _deleteSecretBestEffort(token.id);
      if (previousRow != null && previousRow.tokenHash != tokenHash) {
        await _deleteSecretBestEffort(previousRow.tokenHash);
      }
    }
  }
}
