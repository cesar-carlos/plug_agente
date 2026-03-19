import 'dart:convert';
import 'dart:developer' as developer;

import 'package:jose/jose.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
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
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Future<JwksConfig?> Function() _getConfig;
  final int failureThreshold;
  final Duration circuitOpenDuration;
  final DateTime Function() _now;
  int _consecutiveFailures = 0;
  DateTime? _circuitOpenUntil;

  Future<Result<Map<String, dynamic>>> verify(String token) async {
    final now = _now();
    if (_isCircuitOpen(now)) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'JWKS verification temporarily unavailable',
          context: {
            'authentication': true,
            'reason': 'jwks_circuit_open',
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

    final config = await _getConfig();
    if (config == null || config.jwksUrl.trim().isEmpty) {
      final result = Failure<Map<String, dynamic>, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'JWKS validation is enabled but JWKS URL is not configured',
          context: {
            'authentication': true,
            'reason': 'invalid_jwks_config',
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
            message: 'Token algorithm "none" or missing is not allowed',
            context: {
              'authentication': true,
              'reason': 'invalid_token_signature',
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
              'reason': 'invalid_token_signature',
            },
          ),
        );
        return _finalizeResult(result);
      }

      final keyStore = JsonWebKeyStore()..addKeySetUrl(Uri.parse(config.jwksUrl));

      final verified = await JsonWebToken.decodeAndVerify(
        rawToken,
        keyStore,
        allowedArguments: config.allowedAlgorithms,
      );

      final claims = verified.claims;
      final now = DateTime.now();

      if (claims.expiry != null && claims.expiry!.isBefore(now)) {
        final result = Failure<Map<String, dynamic>, Exception>(
          domain.ConfigurationFailure.withContext(
            message: 'Token has expired',
            context: {
              'authentication': true,
              'reason': 'token_expired',
            },
          ),
        );
        return _finalizeResult(result);
      }

      if (claims.notBefore != null && claims.notBefore!.isAfter(now)) {
        final result = Failure<Map<String, dynamic>, Exception>(
          domain.ConfigurationFailure.withContext(
            message: 'Token is not yet valid',
            context: {
              'authentication': true,
              'reason': 'token_not_yet_valid',
            },
          ),
        );
        return _finalizeResult(result);
      }

      if (config.issuer != null && config.issuer!.isNotEmpty) {
        final expectedIssuer = Uri.tryParse(config.issuer!);
        final actualIssuer = claims.issuer;
        if (expectedIssuer != null && (actualIssuer == null || actualIssuer.toString() != config.issuer)) {
          final result = Failure<Map<String, dynamic>, Exception>(
            domain.ConfigurationFailure.withContext(
              message:
                  'Token issuer "${actualIssuer ?? "null"}" does not match '
                  'expected "${config.issuer}"',
              context: {
                'authentication': true,
                'reason': 'invalid_token_signature',
              },
            ),
          );
          return _finalizeResult(result);
        }
      }

      if (config.audience != null && config.audience!.isNotEmpty) {
        final aud = claims.audience;
        if (aud == null || !aud.contains(config.audience)) {
          final result = Failure<Map<String, dynamic>, Exception>(
            domain.ConfigurationFailure.withContext(
              message: 'Token audience does not contain expected "${config.audience}"',
              context: {
                'authentication': true,
                'reason': 'invalid_token_signature',
              },
            ),
          );
          return _finalizeResult(result);
        }
      }

      final payload = claims.toJson();
      final result = Success<Map<String, dynamic>, Exception>(payload);
      return _finalizeResult(result);
    } on JoseException catch (error) {
      final result = Failure<Map<String, dynamic>, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Token verification failed: ${error.message}',
          cause: error,
          context: {
            'authentication': true,
            'reason': 'invalid_token_signature',
          },
        ),
      );
      return _finalizeResult(result);
    } on Exception catch (error) {
      final result = Failure<Map<String, dynamic>, Exception>(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to verify token',
          cause: error,
          context: {
            'authentication': true,
            'reason': 'invalid_token_signature',
          },
        ),
      );
      return _finalizeResult(result);
    }
  }

  Result<Map<String, dynamic>> _finalizeResult(
    Result<Map<String, dynamic>> result,
  ) {
    if (result.isSuccess()) {
      _consecutiveFailures = 0;
      _circuitOpenUntil = null;
      return result;
    }

    _consecutiveFailures++;
    if (_consecutiveFailures >= failureThreshold) {
      _circuitOpenUntil = _now().add(circuitOpenDuration);
    }
    return result;
  }

  bool _isCircuitOpen(DateTime now) {
    final until = _circuitOpenUntil;
    if (until == null) {
      return false;
    }
    if (now.isAfter(until)) {
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
      final header = jsonDecode(decoded) as Map<String, dynamic>;
      return header['alg'] as String?;
    } on Exception catch (e, stackTrace) {
      developer.log(
        'JWT header parsing failed (malformed or invalid token)',
        name: 'jwt_jwks_verifier',
        error: e,
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
