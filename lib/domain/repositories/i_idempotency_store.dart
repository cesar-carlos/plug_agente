import 'package:plug_agente/domain/protocol/protocol.dart';

class IdempotencyRecord {
  const IdempotencyRecord({
    required this.response,
    required this.requestFingerprint,
  });

  final RpcResponse response;
  final String? requestFingerprint;
}

/// Store for idempotent RPC responses with TTL.
///
/// When a request includes `idempotency_key`, a duplicate request
/// within the TTL window returns the cached response without re-executing.
abstract class IIdempotencyStore {
  Future<IdempotencyRecord?> getRecord(String key);

  Future<RpcResponse?> get(String key);

  Future<void> set(
    String key,
    RpcResponse response,
    Duration ttl, {
    String? requestFingerprint,
  });

  Future<int> purgeExpiredEntries({DateTime? referenceTime});
}
