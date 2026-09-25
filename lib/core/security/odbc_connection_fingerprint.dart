import 'dart:convert';

import 'package:crypto/crypto.dart';

/// Stable DSN label for logs. Never includes host, user, or password.
abstract final class OdbcConnectionFingerprint {
  static String of(String connectionString) {
    return '${_label(connectionString)}:${hash(connectionString)}';
  }

  static String hash(String value) {
    return sha256.convert(utf8.encode(value)).toString().substring(0, 16);
  }

  static String _label(String connectionString) {
    return _attribute(connectionString, 'driver') ?? _attribute(connectionString, 'dsn') ?? 'unknown';
  }

  static String? _attribute(String connectionString, String name) {
    final pattern = RegExp('$name=([^;]+)', caseSensitive: false);
    final match = pattern.firstMatch(connectionString);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }
}
