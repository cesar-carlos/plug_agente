import 'package:jose/jose.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/dio_jwks_key_store.dart';
import 'package:result_dart/result_dart.dart';

/// Caches `JsonWebKeyStore` instances per JWKS URL with a fixed TTL starting at the first successful use.
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
    return DioJwksKeyStore(jwksUri);
  }

  void invalidate() {
    _jwksCacheUrl = null;
    _jwksCachedStore = null;
    _jwksCacheExpiresAt = null;
  }

  Result<JsonWebKeyStore> resolve(String jwksUrl) {
    final uri = Uri.tryParse(jwksUrl);
    if (uri == null || !uri.isAbsolute || (uri.scheme != 'http' && uri.scheme != 'https') || uri.host.isEmpty) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'JWKS URL must be an absolute HTTP or HTTPS endpoint',
          context: {
            'authentication': true,
            'reason': AuthorizationContextConstants.invalidJwksConfigReason,
            'user_message': 'URL JWKS invalida. Configure um endereco HTTP ou HTTPS completo com servidor.',
          },
        ),
      );
    }
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
      return Success(_jwksCachedStore!);
    }
    return Success(_createKeyStore(uri));
  }

  void remember(String jwksUrl, JsonWebKeyStore store) {
    if (_jwksCacheUrl == jwksUrl && identical(_jwksCachedStore, store)) return;
    _jwksCacheUrl = jwksUrl;
    _jwksCachedStore = store;
    _jwksCacheExpiresAt = _now().add(jwksCacheTtl);
  }
}
