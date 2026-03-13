import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

class ClientTokenLocalDataSource {
  ClientTokenLocalDataSource(this._database);

  final AppDatabase _database;
  final Random _random = Random.secure();

  Future<String> createToken(ClientTokenCreateRequest request) async {
    final now = DateTime.now().toUtc();
    final tokenId = _buildTokenId();
    final opaqueToken = _generateOpaqueToken();
    final tokenHash = _hashToken(opaqueToken);
    final summary = ClientTokenSummary(
      id: tokenId,
      clientId: request.clientId.trim(),
      createdAt: now,
      isRevoked: false,
      allTables: request.allTables,
      allViews: request.allViews,
      allPermissions: request.allPermissions,
      rules: request.rules,
      agentId: request.agentId?.trim().isEmpty ?? true ? null : request.agentId,
      payload: request.payload,
    );

    await _database.into(_database.clientTokenCacheTable).insertOnConflictUpdate(
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

  Future<List<ClientTokenSummary>> listTokens() async {
    final rows =
        await (_database.select(_database.clientTokenCacheTable)..orderBy([
              (table) => OrderingTerm(
                expression: table.createdAt,
                mode: OrderingMode.desc,
              ),
            ]))
            .get();

    return rows.map(_toEntity).toList();
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
    final affectedRows =
        await (_database.update(
          _database.clientTokenCacheTable,
        )..where((table) => table.id.equals(tokenId))).write(
          ClientTokenCacheTableCompanion(
            isRevoked: const Value(true),
            syncedAt: Value(DateTime.now().toUtc()),
          ),
        );
    return affectedRows > 0;
  }

  Future<bool> updateToken(
    String tokenId,
    ClientTokenCreateRequest request,
  ) async {
    final affectedRows =
        await (_database.update(
          _database.clientTokenCacheTable,
        )..where((table) => table.id.equals(tokenId))).write(
          ClientTokenCacheTableCompanion(
            clientId: Value(request.clientId.trim()),
            agentId: Value(
              request.agentId?.trim().isEmpty ?? true ? null : request.agentId,
            ),
            payloadJson: Value(jsonEncode(request.payload)),
            allTables: Value(request.allTables),
            allViews: Value(request.allViews),
            allPermissions: Value(request.allPermissions),
            rulesJson: Value(
              jsonEncode(request.rules.map((rule) => rule.toJson()).toList()),
            ),
            syncedAt: Value(DateTime.now().toUtc()),
          ),
        );
    return affectedRows > 0;
  }

  Future<bool> deleteToken(String tokenId) async {
    final affectedRows =
        await (_database.delete(_database.clientTokenCacheTable)
              ..where((table) => table.id.equals(tokenId)))
            .go();
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
      createdAt: token.createdAt.toUtc(),
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

  ClientTokenSummary _toEntity(ClientTokenCacheData row) {
    return ClientTokenSummary(
      id: row.id,
      clientId: row.clientId,
      createdAt: row.createdAt,
      isRevoked: row.isRevoked,
      agentId: row.agentId,
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
}
