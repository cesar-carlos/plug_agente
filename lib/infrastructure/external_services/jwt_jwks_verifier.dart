import 'dart:convert';

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
  JwtJwksVerifier(this._getConfig);

  final Future<JwksConfig?> Function() _getConfig;

  Future<Result<Map<String, dynamic>>> verify(String token) async {
    final rawToken = _normalizeToken(token);
    if (rawToken.isEmpty) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Missing client token',
          context: {'authentication': true},
        ),
      );
    }

    final config = await _getConfig();
    if (config == null || config.jwksUrl.trim().isEmpty) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'JWKS validation is enabled but JWKS URL is not configured',
          context: {
            'authentication': true,
            'reason': 'invalid_jwks_config',
          },
        ),
      );
    }

    try {
      final alg = _getAlgorithmFromHeader(rawToken);

      if (alg == null || alg == 'none') {
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Token algorithm "none" or missing is not allowed',
            context: {
              'authentication': true,
              'reason': 'invalid_token_signature',
            },
          ),
        );
      }

      if (!config.allowedAlgorithms.contains(alg)) {
        return Failure(
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
      }

      final keyStore = JsonWebKeyStore()
        ..addKeySetUrl(Uri.parse(config.jwksUrl));

      final verified = await JsonWebToken.decodeAndVerify(
        rawToken,
        keyStore,
        allowedArguments: config.allowedAlgorithms,
      );

      final claims = verified.claims;
      final now = DateTime.now();

      if (claims.expiry != null && claims.expiry!.isBefore(now)) {
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Token has expired',
            context: {
              'authentication': true,
              'reason': 'token_expired',
            },
          ),
        );
      }

      if (claims.notBefore != null && claims.notBefore!.isAfter(now)) {
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Token is not yet valid',
            context: {
              'authentication': true,
              'reason': 'token_not_yet_valid',
            },
          ),
        );
      }

      if (config.issuer != null && config.issuer!.isNotEmpty) {
        final expectedIssuer = Uri.tryParse(config.issuer!);
        final actualIssuer = claims.issuer;
        if (expectedIssuer != null &&
            (actualIssuer == null ||
                actualIssuer.toString() != config.issuer)) {
          return Failure(
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
        }
      }

      if (config.audience != null && config.audience!.isNotEmpty) {
        final aud = claims.audience;
        if (aud == null || !aud.contains(config.audience)) {
          return Failure(
            domain.ConfigurationFailure.withContext(
              message:
                  'Token audience does not contain expected "${config.audience}"',
              context: {
                'authentication': true,
                'reason': 'invalid_token_signature',
              },
            ),
          );
        }
      }

      final payload = claims.toJson();
      return Success(payload);
    } on JoseException catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Token verification failed: ${error.message}',
          cause: error,
          context: {
            'authentication': true,
            'reason': 'invalid_token_signature',
          },
        ),
      );
    } on Exception catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to verify token',
          cause: error,
          context: {
            'authentication': true,
            'reason': 'invalid_token_signature',
          },
        ),
      );
    }
  }

  String? _getAlgorithmFromHeader(String token) {
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final normalized = base64Url.normalize(parts[0]);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final header = jsonDecode(decoded) as Map<String, dynamic>;
      return header['alg'] as String?;
    } on Exception {
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
