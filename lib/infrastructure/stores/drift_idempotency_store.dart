import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';
import 'package:plug_agente/infrastructure/repositories/agent_config_drift_database.dart';

/// SQLite-backed idempotency cache with TTL and LRU-style eviction.
class DriftIdempotencyStore implements IIdempotencyStore {
  DriftIdempotencyStore(
    this._db, {
    int maxEntries = 8192,
    DateTime Function()? nowProvider,
  }) : _maxEntries = maxEntries,
       _nowProvider = nowProvider ?? DateTime.now {
    if (_maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be >= 1');
    }
  }

  final AppDatabase _db;
  final int _maxEntries;
  final DateTime Function() _nowProvider;

  @override
  Future<IdempotencyRecord?> getRecord(String key) async {
    final now = _nowProvider();
    await _deleteExpired(now);

    final row = await (_db.select(_db.rpcIdempotencyCacheTable)..where((t) => t.cacheKey.equals(key))).getSingleOrNull();
    if (row == null) {
      return null;
    }

    if (row.expiresAt.isBefore(now)) {
      await (_db.delete(_db.rpcIdempotencyCacheTable)..where((t) => t.cacheKey.equals(key))).go();
      return null;
    }

    await (_db.update(_db.rpcIdempotencyCacheTable)..where((t) => t.cacheKey.equals(key))).write(
      RpcIdempotencyCacheTableCompanion(
        updatedAt: Value(now),
      ),
    );

    final parsed = _parseResponse(row.responseJson);
    if (parsed == null) {
      await (_db.delete(_db.rpcIdempotencyCacheTable)..where((t) => t.cacheKey.equals(key))).go();
      return null;
    }

    return IdempotencyRecord(
      response: parsed,
      requestFingerprint: row.requestFingerprint,
    );
  }

  @override
  Future<RpcResponse?> get(String key) async => (await getRecord(key))?.response;

  @override
  Future<void> set(
    String key,
    RpcResponse response,
    Duration ttl, {
    String? requestFingerprint,
  }) async {
    final now = _nowProvider();
    await _deleteExpired(now);

    final effectiveTtl = ttl <= Duration.zero ? ConnectionConstants.rpcIdempotencyEntryTtl : ttl;
    final expiresAt = now.add(effectiveTtl);

    final count = await _countRows();
    if (count >= _maxEntries) {
      final excess = count - _maxEntries + 1;
      await _evictOldest(excess);
    }

    final jsonText = jsonEncode(response.toJson());
    await _db.into(_db.rpcIdempotencyCacheTable).insertOnConflictUpdate(
      RpcIdempotencyCacheTableCompanion.insert(
        cacheKey: key,
        responseJson: jsonText,
        requestFingerprint: requestFingerprint == null ? const Value.absent() : Value(requestFingerprint),
        expiresAt: expiresAt,
        updatedAt: now,
      ),
    );
  }

  Future<int> _deleteExpired(DateTime now) {
    return (_db.delete(_db.rpcIdempotencyCacheTable)..where((t) => t.expiresAt.isSmallerThanValue(now))).go();
  }

  @override
  Future<int> purgeExpiredEntries({DateTime? referenceTime}) {
    return _deleteExpired(referenceTime ?? _nowProvider());
  }

  Future<int> _countRows() async {
    final row = await _db.customSelect(
      'SELECT COUNT(*) AS c FROM rpc_idempotency_cache_table',
      readsFrom: {_db.rpcIdempotencyCacheTable},
    ).getSingle();
    return row.read<int>('c');
  }

  Future<void> _evictOldest(int count) async {
    if (count <= 0) {
      return;
    }
    await _db.customStatement(
      'DELETE FROM rpc_idempotency_cache_table WHERE cache_key IN (SELECT cache_key FROM rpc_idempotency_cache_table ORDER BY updated_at ASC LIMIT ?)',
      [count],
    );
  }

  RpcResponse? _parseResponse(String jsonText) {
    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }

      return RpcResponse.fromJson(decoded);
    } on FormatException {
      return null;
    } on Object {
      return null;
    }
  }
}
