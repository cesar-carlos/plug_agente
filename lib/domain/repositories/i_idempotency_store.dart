import 'package:plug_agente/domain/protocol/protocol.dart';

/// Store for idempotent RPC responses with TTL.
///
/// When a request includes `idempotency_key`, a duplicate request
/// within the TTL window returns the cached response without re-executing.
abstract class IIdempotencyStore {
  /// Returns cached response for [key], or null if not found or expired.
  RpcResponse? get(String key);

  /// Stores [response] for [key] with [ttl] duration.
  void set(String key, RpcResponse response, Duration ttl);
}
