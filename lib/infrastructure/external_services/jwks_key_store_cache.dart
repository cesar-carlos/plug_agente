import 'package:jose/jose.dart';

/// Caches `JsonWebKeyStore` instances per JWKS URL with TTL after successful use.
///
/// Extracted from `JwtJwksVerifier` for focused unit tests and reuse.
class JwksKeyStoreCache {
  JwksKeyStoreCache({
    required this.jwksCacheTtl,
    required DateTime Function() now,
    JsonWebKeyStore Function(Uri jwksUri)? createKeyStore,
  }) : _now = now,
       _createKeyStore = createKeyStore ?? _defaultCreateKeyStore;

  final Duration jwksCacheTtl;
  final DateTime Function() _now;
  final JsonWebKeyStore Function(Uri) _createKeyStore;

  String? _jwksCacheUrl;
  JsonWebKeyStore? _jwksCachedStore;
  DateTime? _jwksCacheExpiresAt;

  static JsonWebKeyStore _defaultCreateKeyStore(Uri jwksUri) {
    return JsonWebKeyStore()..addKeySetUrl(jwksUri);
  }

  JsonWebKeyStore resolve(String jwksUrl) {
    if (jwksUrl != _jwksCacheUrl) {
      _jwksCacheUrl = null;
      _jwksCachedStore = null;
      _jwksCacheExpiresAt = null;
    }
    final now = _now();
    if (_jwksCachedStore != null &&
        _jwksCacheUrl == jwksUrl &&
        _jwksCacheExpiresAt != null &&
        now.isBefore(_jwksCacheExpiresAt!)) {
      return _jwksCachedStore!;
    }
    return _createKeyStore(Uri.parse(jwksUrl));
  }

  void remember(String jwksUrl, JsonWebKeyStore store) {
    _jwksCacheUrl = jwksUrl;
    _jwksCachedStore = store;
    _jwksCacheExpiresAt = _now().add(jwksCacheTtl);
  }
}
