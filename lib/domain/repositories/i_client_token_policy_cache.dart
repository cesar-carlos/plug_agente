import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:result_dart/result_dart.dart';

/// Result of joining (or starting) a policy resolution.
///
/// [isCurrent] is false when an update, revocation, or deletion invalidated the
/// credential while its backing lookup was still running. Callers must discard
/// that result and resolve again; this prevents a stale lookup from reviving a
/// policy after an invalidation.
final class ClientTokenPolicyResolution {
  const ClientTokenPolicyResolution({
    required this.result,
    required this.isCurrent,
  });

  final Result<ClientTokenPolicy> result;
  final bool isCurrent;
}

/// Resolved [ClientTokenPolicy] cache keyed by the app credential hash
/// (normalized token, SHA-256 hex).
abstract class IClientTokenPolicyCache {
  ClientTokenPolicy? get(String credentialHash);

  void put(String credentialHash, ClientTokenPolicy policy);

  void invalidate(String credentialHash);

  void invalidateAll();

  /// True when a lookup for [credentialHash] is already shared by callers.
  bool hasPendingResolution(String credentialHash);

  /// Shares one backing policy lookup per normalized credential hash.
  ///
  /// Only a successful, still-current resolution is retained in the cache.
  Future<ClientTokenPolicyResolution> resolveSingleFlight(
    String credentialHash,
    Future<Result<ClientTokenPolicy>> Function() loader,
  );
}
