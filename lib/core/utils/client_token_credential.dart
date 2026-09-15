import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Trims and strips a leading `Bearer ` prefix (case-insensitive).
String normalizeClientCredentialToken(String token) {
  var value = token.trim();
  if (value.length > 7 && value.toLowerCase().startsWith('bearer ')) {
    value = value.substring(7).trim();
  }
  return value;
}

/// SHA-256 (hex) of UTF-8 bytes of [normalizeClientCredentialToken].
///
/// Used for authorization decision keys and policy cache keys so the same
/// credential string yields one stable identifier.
String hashClientCredentialToken(String token) =>
    sha256.convert(utf8.encode(normalizeClientCredentialToken(token))).toString();

/// Extracts the documented client credential aliases from JSON-RPC params.
///
/// The caller receives the original token form so the authorization boundary
/// can normalize it exactly once before hashing or resolving a policy.
String? extractClientTokenFromRpcParams(Object? params) {
  if (params is! Map<String, dynamic>) return null;
  final raw = params['client_token'] ?? params['auth'] ?? params['clientToken'];
  return raw is String && raw.trim().isNotEmpty ? raw.trim() : null;
}
