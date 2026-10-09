import 'package:plug_agente/core/utils/client_token_credential.dart';
import 'package:plug_agente/domain/repositories/i_revoked_token_store.dart';

/// In-memory revoked token store with TTL.
///
/// Stores a hash of each token to avoid retaining raw tokens.
/// Entries expire after the configured TTL.
class InMemoryRevokedTokenStore implements IRevokedTokenStore {
  InMemoryRevokedTokenStore({
    Duration? defaultTtl,
    DateTime Function()? nowProvider,
  }) : _defaultTtl = defaultTtl ?? const Duration(hours: 1),
       _nowProvider = nowProvider ?? DateTime.now;

  final Duration _defaultTtl;
  final DateTime Function() _nowProvider;

  final Map<String, DateTime> _store = <String, DateTime>{};

  @override
  bool isRevoked(String token) {
    final key = hashClientCredentialToken(token);
    final expiresAt = _store[key];
    if (expiresAt == null) return false;
    if (_nowProvider().isAfter(expiresAt)) {
      _store.remove(key);
      return false;
    }
    return true;
  }

  @override
  void add(String token) => addCredentialHash(hashClientCredentialToken(token));

  @override
  void addCredentialHash(String credentialHash) {
    _store[credentialHash] = _nowProvider().add(_defaultTtl);
  }
}
