import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:math';

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

    await _database
        .into(_database.clientTokenCacheTable)
        .insertOnConflictUpdate(_toCompanion(summary, syncedAt: now));

    return _buildClientToken(summary);
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

  ClientTokenCacheTableCompanion _toCompanion(
    ClientTokenSummary token, {
    required DateTime syncedAt,
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

  String _buildClientToken(ClientTokenSummary token) {
    final header = <String, dynamic>{
      'alg': 'none',
      'typ': 'JWT',
    };
    final payload = <String, dynamic>{
      'jti': token.id,
      'iat': token.createdAt.millisecondsSinceEpoch ~/ 1000,
      'policy': token.toJson(),
    };

    final headerSegment = _encodeSegment(header);
    final payloadSegment = _encodeSegment(payload);
    return '$headerSegment.$payloadSegment.';
  }

  String _encodeSegment(Map<String, dynamic> value) {
    final json = jsonEncode(value);
    return base64Url.encode(utf8.encode(json)).replaceAll('=', '');
  }

  String _buildTokenId() {
    final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch.toString();
    final suffix = _random.nextInt(1 << 20).toRadixString(16);
    return '${timestamp}_$suffix';
  }
}
