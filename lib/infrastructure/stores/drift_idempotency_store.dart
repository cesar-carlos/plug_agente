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
    Duration lruUpdateMinInterval = _defaultLruUpdateMinInterval,
    DateTime Function()? nowProvider,
  }) : _maxEntries = maxEntries,
       _lruUpdateMinInterval = lruUpdateMinInterval,
       _nowProvider = nowProvider ?? DateTime.now {
    if (_maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be >= 1');
    }
    if (_lruUpdateMinInterval < Duration.zero) {
      throw ArgumentError.value(
        lruUpdateMinInterval,
        'lruUpdateMinInterval',
        'must be non-negative',
      );
    }
  }

  /// Default minimum interval between `updated_at` touches for LRU tracking.
  ///
  /// A hot key hit 100 times per second would otherwise generate 100 SQLite
  /// writes per second just for LRU bookkeeping. Throttling to once per minute
  /// keeps the LRU order good enough for an 8192-entry cache while removing
  /// the redundant write traffic.
  static const Duration _defaultLruUpdateMinInterval = Duration(minutes: 1);

  final AppDatabase _db;
  final int _maxEntries;
  final Duration _lruUpdateMinInterval;
  final DateTime Function() _nowProvider;

  @override
  Future<IdempotencyRecord?> getRecord(String key) async {
    final now = _nowProvider();
    // No bulk delete here: the per-row TTL check below handles the requested
    // key, and the periodic purge (every 15 min) handles the rest. Running a
    // DELETE on every read adds unnecessary write I/O on the hot path.

    final row = await (_db.select(
      _db.rpcIdempotencyCacheTable,
    )..where((t) => t.cacheKey.equals(key))).getSingleOrNull();
    if (row == null) {
      return null;
    }

    if (row.expiresAt.isBefore(now)) {
      await (_db.delete(_db.rpcIdempotencyCacheTable)..where((t) => t.cacheKey.equals(key))).go();
      return null;
    }

    // Throttle LRU `updated_at` touches: skip when the existing timestamp is
    // recent enough that the LRU ordering would not change meaningfully. This
    // removes redundant SQLite writes on hot keys without degrading eviction
    // accuracy for an 8192-entry cache.
    if (_lruUpdateMinInterval <= Duration.zero ||
        now.difference(row.updatedAt) >= _lruUpdateMinInterval) {
      await (_db.update(_db.rpcIdempotencyCacheTable)..where((t) => t.cacheKey.equals(key))).write(
        RpcIdempotencyCacheTableCompanion(
          updatedAt: Value(now),
        ),
      );
    }

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
    final effectiveTtl = ttl <= Duration.zero ? ConnectionConstants.rpcIdempotencyEntryTtl : ttl;
    final expiresAt = now.add(effectiveTtl);
    final jsonText = jsonEncode(response.toJson());

    // Wrap the writes in a transaction: count, evict and insert must succeed
    // or fail atomically. Without it, a crash between eviction and insert
    // would leave the cache below capacity but missing the entry the caller
    // intended to persist.
    //
    // We intentionally do NOT purge expired entries here: the periodic purge
    // (every `rpcIdempotencyExpiredPurgeInterval`) handles that, and the LRU
    // eviction below naturally evicts expired entries first because they have
    // the oldest `updated_at`. Skipping the per-set DELETE saves one SQLite
    // write op on every cache write, which adds up under high RPC throughput.
    await _db.transaction(() async {
      final count = await _countRows();
      if (count >= _maxEntries) {
        final excess = count - _maxEntries + 1;
        await _evictOldest(excess);
      }
      await _db
          .into(_db.rpcIdempotencyCacheTable)
          .insertOnConflictUpdate(
            RpcIdempotencyCacheTableCompanion.insert(
              cacheKey: key,
              responseJson: jsonText,
              requestFingerprint: requestFingerprint == null ? const Value.absent() : Value(requestFingerprint),
              expiresAt: expiresAt,
              updatedAt: now,
            ),
          );
    });
  }

  Future<int> _deleteExpired(DateTime now) {
    return (_db.delete(_db.rpcIdempotencyCacheTable)..where((t) => t.expiresAt.isSmallerThanValue(now))).go();
  }

  @override
  Future<int> purgeExpiredEntries({DateTime? referenceTime}) {
    return _deleteExpired(referenceTime ?? _nowProvider());
  }

  Future<int> _countRows() async {
    final row = await _db
        .customSelect(
          'SELECT COUNT(*) AS c FROM rpc_idempotency_cache_table',
          readsFrom: {_db.rpcIdempotencyCacheTable},
        )
        .getSingle();
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
