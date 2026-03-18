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
  /// Returns cached record for [key], or null if not found or expired.
  IdempotencyRecord? getRecord(String key);

  /// Returns cached response for [key], or null if not found or expired.
  RpcResponse? get(String key) => getRecord(key)?.response;

  /// Stores [response] for [key] with [ttl] duration.
  void set(
    String key,
    RpcResponse response,
    Duration ttl, {
    String? requestFingerprint,
  });
}
