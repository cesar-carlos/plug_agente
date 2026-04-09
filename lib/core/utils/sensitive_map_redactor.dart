/// Redacts values for keys that look like secrets before exposing maps on RPC boundaries.
class SensitiveMapRedactor {
  SensitiveMapRedactor._();

  /// Keys that are never redacted even when they contain substrings such as "token"
  /// (e.g. operational metadata, not secret material).
  static const Set<String> _neverRedactExactKeys = {
    'token_scope',
    'tokenization_mode',
    'token_kind',
    'token_type',
    'token_format',
  };

  static const Set<String> _sensitiveExactKeys = {
    'password',
    'token',
    'secret',
    'apikey',
    'api_key',
    'accesstoken',
    'access_token',
    'refreshtoken',
    'refresh_token',
    'connectionstring',
    'connection_string',
    'authorization',
    'private_key',
    'privatekey',
    'client_secret',
  };

  /// Substrings that strongly indicate a secret-bearing field (avoid bare `token` here;
  /// use [_tokenLikeKey] for token-shaped names).
  static const Set<String> _sensitiveSubstrings = {
    'password',
    'passwd',
    'secret',
    'apikey',
    'api_key',
    'privatekey',
    'private_key',
    'connectionstring',
    'connection_string',
    'accesstoken',
    'access_token',
    'refreshtoken',
    'refresh_token',
    'client_secret',
    'credential',
    'credentials',
    'bearer',
  };

  static bool isSensitiveKey(String key) {
    final lower = key.toLowerCase();
    if (_neverRedactExactKeys.contains(lower)) {
      return false;
    }
    if (_sensitiveExactKeys.contains(lower)) {
      return true;
    }
    for (final fragment in _sensitiveSubstrings) {
      if (lower.contains(fragment)) {
        return true;
      }
    }
    return _tokenLikeKey(lower);
  }

  /// True for keys that denote a secret token value (not allowlisted metadata).
  static bool _tokenLikeKey(String lower) {
    if (lower == 'token') {
      return true;
    }
    if (lower.endsWith('_token')) {
      return true;
    }
    if (lower.endsWith('token') && lower.length > 'token'.length) {
      final before = lower.substring(0, lower.length - 'token'.length);
      if (before.isEmpty) {
        return false;
      }
      final last = before[before.length - 1];
      return last == '_' || last == '-' || last == '.';
    }
    return false;
  }

  static Map<String, dynamic> redactForRpc(Map<String, dynamic> source) {
    return Map<String, dynamic>.fromEntries(
      source.entries.map((MapEntry<String, dynamic> e) {
        if (isSensitiveKey(e.key)) {
          return MapEntry<String, dynamic>(e.key, '[REDACTED]');
        }
        final value = e.value;
        if (value is Map<String, dynamic>) {
          return MapEntry<String, dynamic>(e.key, redactForRpc(value));
        }
        if (value is Map) {
          return MapEntry<String, dynamic>(
            e.key,
            redactForRpc(Map<String, dynamic>.from(value)),
          );
        }
        if (value is List) {
          return MapEntry<String, dynamic>(e.key, _redactList(value));
        }
        return MapEntry<String, dynamic>(e.key, value);
      }),
    );
  }

  static List<dynamic> _redactList(List<dynamic> list) {
    return list.map((Object? item) {
      if (item is Map<String, dynamic>) {
        return redactForRpc(item);
      }
      if (item is Map) {
        return redactForRpc(Map<String, dynamic>.from(item));
      }
      if (item is List) {
        return _redactList(item);
      }
      return item;
    }).toList();
  }
}
