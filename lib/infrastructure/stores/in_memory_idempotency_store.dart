import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/domain/repositories/i_idempotency_store.dart';

/// In-memory idempotency store with TTL.
///
/// Entries expire after the configured TTL and are cleaned up on access.
class InMemoryIdempotencyStore implements IIdempotencyStore {
  InMemoryIdempotencyStore({
    Duration? defaultTtl,
    DateTime Function()? nowProvider,
  }) : _defaultTtl = defaultTtl ?? const Duration(minutes: 5),
       _nowProvider = nowProvider ?? DateTime.now;

  final Duration _defaultTtl;
  final DateTime Function() _nowProvider;

  final Map<String, _Entry> _store = <String, _Entry>{};

  @override
  RpcResponse? get(String key) {
    final entry = _store[key];
    if (entry == null) return null;
    if (_nowProvider().isAfter(entry.expiresAt)) {
      _store.remove(key);
      return null;
    }
    return entry.response;
  }

  @override
  void set(String key, RpcResponse response, Duration ttl) {
    final effectiveTtl = ttl == Duration.zero ? _defaultTtl : ttl;
    _store[key] = _Entry(
      response: response,
      expiresAt: _nowProvider().add(effectiveTtl),
    );
  }
}

class _Entry {
  _Entry({required this.response, required this.expiresAt});
  final RpcResponse response;
  final DateTime expiresAt;
}
