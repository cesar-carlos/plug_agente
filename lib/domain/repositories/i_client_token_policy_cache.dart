import 'package:plug_agente/domain/entities/client_token_policy.dart';

/// Resolved [ClientTokenPolicy] cache keyed by the app credential hash
/// (normalized token, SHA-256 hex).
abstract class IClientTokenPolicyCache {
  ClientTokenPolicy? get(String credentialHash);

  void put(String credentialHash, ClientTokenPolicy policy);

  void invalidateAll();
}
