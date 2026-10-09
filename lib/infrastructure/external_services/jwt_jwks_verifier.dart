import 'dart:convert';
import 'dart:developer' as developer;

import 'package:jose/jose.dart';
import 'package:plug_agente/core/constants/authorization_context_constants.dart';
import 'package:plug_agente/core/utils/jwt_numeric_date.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/external_services/jwks_key_store_cache.dart';
import 'package:result_dart/result_dart.dart';

const _defaultAllowedAlgorithms = [
  'RS256',
  'RS384',
  'RS512',
  'ES256',
  'ES384',
  'ES512',
];

class JwksConfig {
  const JwksConfig({
    required this.jwksUrl,
    this.issuer,
    this.audience,
    List<String>? allowedAlgorithms,
  }) : allowedAlgorithms = allowedAlgorithms ?? _defaultAllowedAlgorithms;

  final String jwksUrl;
  final String? issuer;
  final String? audience;
  final List<String> allowedAlgorithms;
}

class JwtJwksVerifier {
  JwtJwksVerifier(
    this._getConfig, {
    this.failureThreshold = 3,
    this.circuitOpenDuration = const Duration(seconds: 30),
    this.jwksCacheTtl = const Duration(minutes: 5),
    DateTime Function()? now,
    JsonWebKeyStore Function(Uri jwksUri)? createKeyStore,
  }) : _now = now ?? DateTime.now,
       _jwksKeyStoreCache = JwksKeyStoreCache(
         jwksCacheTtl: jwksCacheTtl,
         now: now ?? DateTime.now,
         createKeyStore: createKeyStore,
       );

  final Future<JwksConfig?> Function() _getConfig;
  final int failureThreshold;
  final Duration circuitOpenDuration;
  final Duration jwksCacheTtl;
  final DateTime Function() _now;
  final JwksKeyStoreCache _jwksKeyStoreCache;
  int _trustRevision = 0;
  int _consecutiveFailures = 0;
  DateTime? _circuitOpenUntil;

  Future<Result<Map<String, dynamic>>> verify(String token) async {
    final trustRevision = _trustRevision;
    final now = _now();
    if (_isCircuitOpen(now)) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'JWKS verification temporarily unavailable',
          context: {
            'authentication': true,
            'reason': AuthorizationContextConstants.jwksCircuitOpenReason,
            'retryable': true,
            'retry_after': _circuitOpenUntil?.toUtc().toIso8601String(),
          },
        ),
      );
    }

    final rawToken = _normalizeToken(token);
    if (rawToken.isEmpty) {
      final result = Failure<Map<String, dynamic>, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Missing client token',
          context: {'authentication': true},
        ),
      );
      return _finalizeResult(result);
    }

    final JwksConfig? config;
    try {
      config = await _getConfig();
    } on Exception catch (error) {
      if (trustRevision != _trustRevision) return verify(token);
      return _finalizeResult(
        Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Failed to read JWKS configuration',
            cause: error,
            context: {
              'authentication': true,
              'reason': AuthorizationContextConstants.invalidJwksConfigReason,
              'user_message':
                  'Nao foi possivel ler a configuracao JWKS. Confira a configuracao do agente e tente novamente.',
            },
          ),
        ),
        countInCircuit: true,
      );
    }
    if (trustRevision != _trustRevision) return verify(token);
    if (config == null || config.jwksUrl.trim().isEmpty) {
      final result = Failure<Map<String, dynamic>, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'JWKS validation is enabled but JWKS URL is not configured',
          context: {
            'authentication': true,
            'reason': AuthorizationContextConstants.invalidJwksConfigReason,
          },
        ),
      );
      return _finalizeResult(result);
    }

    try {
      final alg = _getAlgorithmFromHeader(rawToken);

      if (alg == null || alg == 'none') {
        final result = Failure<Map<String, dynamic>, Exception>(
          domain.ConfigurationFailure.withContext(
            message: 'Token header or algorithm is invalid or not allowed',
            context: {
              'authentication': true,
              'reason': AuthorizationContextConstants.invalidTokenSignatureReason,
            },
          ),
        );
        return _finalizeResult(result);
      }

      if (!config.allowedAlgorithms.contains(alg)) {
        final result = Failure<Map<String, dynamic>, Exception>(
          domain.ConfigurationFailure.withContext(
            message:
                'Token algorithm "$alg" is not in allowlist: '
                '${config.allowedAlgorithms.join(", ")}',
            context: {
              'authentication': true,
              'reason': AuthorizationContextConstants.invalidTokenSignatureReason,
            },
          ),
        );
        return _finalizeResult(result);
      }

      final parts = rawToken.split('.');
      if (parts.length != 3) throw const FormatException('Invalid compact JWT');
      final rawPayload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      if (rawPayload is! Map<String, dynamic>) throw const FormatException('JWT payload must be an object');
      final storeResult = _jwksKeyStoreCache.resolve(config.jwksUrl);
      if (storeResult.isError()) return _finalizeResult(Failure(storeResult.exceptionOrNull()!));
      final keyStore = storeResult.getOrThrow();

      final verified = await JsonWebToken.decodeAndVerify(
        rawToken,
        _VerificationKeyStore(keyStore),
        allowedArguments: config.allowedAlgorithms,
      );

      if (trustRevision != _trustRevision) return await verify(token);
      final claims = verified.claims;
      final claimsNow = _now();
      final payload = claims.toJson();
      final DateTime? expiry;
      final DateTime? notBefore;
      try {
        _validateIdentityClaims(payload);
        expiry = parseJwtNumericDate(payload['exp'], claim: 'exp');
        notBefore = parseJwtNumericDate(payload['nbf'], claim: 'nbf');
      } on FormatException catch (error) {
        return _finalizeResult(
          Failure(
            domain.ConfigurationFailure.withContext(
              message: 'Invalid token claims',
              cause: error,
              context: {
                'authentication': true,
                'reason': AuthorizationContextConstants.invalidTokenSignatureReason,
                'user_message': 'Token invalido. Gere outro token com identificacao e datas validas.',
              },
            ),
          ),
        );
      }

      if (expiry != null && !claimsNow.isBefore(expiry)) {
        final result = Failure<Map<String, dynamic>, Exception>(
          domain.ConfigurationFailure.withContext(
            message: 'Token has expired',
            context: {
              'authentication': true,
              'reason': AuthorizationContextConstants.tokenExpiredReason,
              'user_message': 'Token expirado. Gere um novo token para continuar.',
            },
          ),
        );
        return _finalizeResult(result);
      }

      if (notBefore != null && claimsNow.isBefore(notBefore)) {
        final result = Failure<Map<String, dynamic>, Exception>(
          domain.ConfigurationFailure.withContext(
            message: 'Token is not yet valid',
            context: {
              'authentication': true,
              'reason': AuthorizationContextConstants.tokenNotYetValidReason,
              'user_message': 'Este token ainda nao esta valido. Aguarde seu horario de ativacao.',
            },
          ),
        );
        return _finalizeResult(result);
      }

      if (config.issuer != null && config.issuer!.isNotEmpty) {
        final configuredIssuer = config.issuer!.trim();
        // Reject if the configured issuer is not a parseable URI — fail closed
        // rather than silently bypassing issuer validation on misconfiguration.
        final expectedIssuer = Uri.tryParse(configuredIssuer);
        if (expectedIssuer == null) {
          final result = Failure<Map<String, dynamic>, Exception>(
            domain.ConfigurationFailure.withContext(
              message: 'JWKS issuer is configured but is not a valid URI: "$configuredIssuer"',
              context: {
                'authentication': true,
                'reason': AuthorizationContextConstants.invalidJwksConfigReason,
              },
            ),
          );
          return _finalizeResult(result);
        }
        final actualIssuer = payload['iss'] as String?;
        if (actualIssuer == null || actualIssuer != configuredIssuer) {
          final result = Failure<Map<String, dynamic>, Exception>(
            domain.ConfigurationFailure.withContext(
              message: 'Token issuer does not match the configured issuer',
              context: {
                'authentication': true,
                'reason': AuthorizationContextConstants.invalidTokenSignatureReason,
              },
            ),
          );
          return _finalizeResult(result);
        }
      }

      if (config.audience != null && config.audience!.isNotEmpty) {
        final aud = payload['aud'];
        final matchesAudience = aud is String ? aud == config.audience : aud is List && aud.contains(config.audience);
        if (!matchesAudience) {
          final result = Failure<Map<String, dynamic>, Exception>(
            domain.ConfigurationFailure.withContext(
              message: 'Token audience does not contain expected "${config.audience}"',
              context: {
                'authentication': true,
                'reason': AuthorizationContextConstants.invalidTokenSignatureReason,
              },
            ),
          );
          return _finalizeResult(result);
        }
      }

      _jwksKeyStoreCache.remember(config.jwksUrl, keyStore);
      final result = Success<Map<String, dynamic>, Exception>(payload);
      return _finalizeResult(result);
    } on _JwksLoadException catch (error) {
      if (trustRevision != _trustRevision) return verify(token);
      return _finalizeResult(
        Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Failed to load JWKS keys',
            cause: error.cause,
            context: {
              'authentication': true,
              'reason': AuthorizationContextConstants.invalidJwksConfigReason,
              'user_message':
                  'Nao foi possivel carregar as chaves JWKS. Confira a conexao com o servidor e tente novamente.',
              'retryable': true,
            },
          ),
        ),
        countInCircuit: true,
      );
    } on JoseException catch (error) {
      final result = Failure<Map<String, dynamic>, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Token signature verification failed',
          cause: error,
          context: {
            'authentication': true,
            'reason': AuthorizationContextConstants.invalidTokenSignatureReason,
          },
        ),
      );
      if (trustRevision != _trustRevision) return verify(token);
      return _finalizeResult(result);
    } on Exception catch (error) {
      final result = Failure<Map<String, dynamic>, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to verify token',
          cause: error,
          context: {
            'authentication': true,
            'reason': AuthorizationContextConstants.invalidTokenSignatureReason,
          },
        ),
      );
      if (trustRevision != _trustRevision) return verify(token);
      return _finalizeResult(result);
    }
  }

  void invalidateTrust() {
    _trustRevision++;
    _consecutiveFailures = 0;
    _circuitOpenUntil = null;
    _jwksKeyStoreCache.invalidate();
  }

  void _validateIdentityClaims(Map<String, dynamic> payload) {
    final issuer = payload['iss'];
    if (issuer != null && issuer is! String) throw const FormatException('JWT issuer must be a string');
    final audience = payload['aud'];
    if (audience != null && audience is! String && (audience is! List || audience.any((value) => value is! String))) {
      throw const FormatException('JWT audience must contain strings');
    }
  }

  // Only infrastructure failures (JWKS network/crypto errors) should count
  // toward the circuit breaker. Client-side token errors (expired, wrong
  // algorithm, issuer mismatch, etc.) must NOT open the circuit — they would
  // block all token verification for 30 s just because one client sent a
  // bad token.
  Result<Map<String, dynamic>> _finalizeResult(
    Result<Map<String, dynamic>> result, {
    bool countInCircuit = false,
  }) {
    if (result.isSuccess()) {
      _consecutiveFailures = 0;
      _circuitOpenUntil = null;
      return result;
    }

    if (countInCircuit) {
      _consecutiveFailures++;
      if (_consecutiveFailures >= failureThreshold) {
        _circuitOpenUntil = _now().add(circuitOpenDuration);
      }
    }
    return result;
  }

  bool _isCircuitOpen(DateTime now) {
    final until = _circuitOpenUntil;
    if (until == null) {
      return false;
    }
    if (!now.isBefore(until)) {
      _circuitOpenUntil = null;
      _consecutiveFailures = 0;
      return false;
    }
    return true;
  }

  String? _getAlgorithmFromHeader(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final normalized = base64Url.normalize(parts[0]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final header = jsonDecode(decoded);
      if (header is! Map<String, dynamic>) {
        return null;
      }
      // Validate external JSON before JOSE's typed accessors can cast it.
      for (final field in ['alg', 'kid', 'cty', 'typ', 'jku', 'enc', 'zip']) {
        if (header.containsKey(field) && header[field] is! String) return null;
      }
      final critical = header['crit'];
      if (header.containsKey('crit') && (critical is! List || critical.any((value) => value is! String))) return null;
      if (header.containsKey('jwk') && header['jwk'] is! Map<String, dynamic>) return null;
      final algorithm = header['alg'];
      return algorithm is String ? algorithm : null;
    } on FormatException catch (error, stackTrace) {
      developer.log(
        'JWT header parsing failed (malformed or invalid token)',
        name: 'jwt_jwks_verifier',
        error: error.runtimeType,
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  String _normalizeToken(String token) {
    final value = token.trim();
    if (value.toLowerCase().startsWith('bearer ')) {
      return value.substring(7).trim();
    }
    return value;
  }
}

class _VerificationKeyStore extends JsonWebKeyStore {
  _VerificationKeyStore(this._delegate);
  final JsonWebKeyStore _delegate;

  @override
  Stream<JsonWebKey?> findJsonWebKeys(JoseHeader header, String operation) async* {
    try {
      await for (final key in _delegate.findJsonWebKeys(header, operation)) {
        yield key;
      }
    } on Exception catch (error) {
      throw _JwksLoadException(error);
    }
  }
}

class _JwksLoadException implements Exception {
  const _JwksLoadException(this.cause);
  final Exception cause;
}
