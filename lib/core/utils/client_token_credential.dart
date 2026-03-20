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
