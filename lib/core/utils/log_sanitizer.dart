/// Sanitizes sensitive data from logs and serialized payloads.
///
/// Matching rules:
/// - **Exact key match** (case-insensitive) against a fixed set of known secret
///   field names (e.g. `password`, `client_token`).
/// - **Suffix match** for common secret patterns (`_token`, `_secret`, etc.) so
///   keys like `access_token` redact without using broad substring search on
///   the whole key (which caused false positives such as `notpassword`
///   containing `password`).
///
/// Large or deeply nested structures are truncated to bound CPU and memory when
/// sanitizing logs.
class LogSanitizer {
  LogSanitizer._();

  static const _exactSensitiveKeys = {
    'password',
    'token',
    'secret',
    'client_token',
    'clienttoken',
    'apikey',
    'api_key',
    'accesstoken',
    'access_token',
    'refreshtoken',
    'refresh_token',
    'connectionstring',
    'connection_string',
    'authorization',
    'bearer',
  };

  static const _sensitiveKeySuffixes = [
    '_token',
    '_secret',
    '_password',
    '_api_key',
  ];

  static const _redacted = '[REDACTED]';
  static const _maxDepth = 24;
  static const _maxListElements = 200;
  static const _maxMapEntries = 200;

  static bool _isSensitiveKey(String key) {
    final lower = key.toLowerCase();
    if (_exactSensitiveKeys.contains(lower)) {
      return true;
    }
    for (final suffix in _sensitiveKeySuffixes) {
      if (lower.endsWith(suffix)) {
        return true;
      }
    }
    return false;
  }

  /// Recursively sanitizes a map, replacing sensitive values.
  static Map<String, dynamic> sanitizeMap(Map<String, dynamic> map) {
    return _sanitizeMapDepth(map, 0);
  }

  static Map<String, dynamic> _sanitizeMapDepth(
    Map<String, dynamic> map,
    int depth,
  ) {
    if (depth > _maxDepth) {
      return {'_truncated': '[MAX_DEPTH]'};
    }
    final out = <String, dynamic>{};
    var count = 0;
    for (final entry in map.entries) {
      if (count >= _maxMapEntries) {
        out['_truncated_entries'] = '[MAP_TRUNCATED]';
        break;
      }
      count++;
      final key = entry.key;
      final value = entry.value;
      if (_isSensitiveKey(key)) {
        out[key] = _redacted;
        continue;
      }
      out[key] = _sanitizeValue(value, depth + 1);
    }
    return out;
  }

  static dynamic _sanitizeValue(dynamic value, int depth) {
    if (depth > _maxDepth) {
      return '[MAX_DEPTH]';
    }
    if (value is Map<String, dynamic>) {
      return _sanitizeMapDepth(value, depth);
    }
    if (value is Map) {
      return _sanitizeMapDepth(Map<String, dynamic>.from(value), depth);
    }
    if (value is List) {
      final take = value.length > _maxListElements ? _maxListElements : value.length;
      final sanitized = <dynamic>[];
      for (var i = 0; i < take; i++) {
        final e = value[i];
        if (e is Map) {
          sanitized.add(_sanitizeMapDepth(Map<String, dynamic>.from(e), depth));
        } else {
          sanitized.add(e);
        }
      }
      if (value.length > _maxListElements) {
        sanitized.add(
          '[LIST_TRUNCATED:${value.length - _maxListElements}_MORE]',
        );
      }
      return sanitized;
    }
    return value;
  }

  /// Sanitizes parameters for query logging.
  static Map<String, dynamic>? sanitizeParameters(
    Map<String, dynamic>? params,
  ) {
    if (params == null || params.isEmpty) return params;
    return sanitizeMap(Map<String, dynamic>.from(params));
  }

  /// Sanitizes dynamic data (map, list, or other) for display.
  static dynamic sanitize(dynamic data) {
    if (data is Map) {
      return _sanitizeMapDepth(Map<String, dynamic>.from(data), 0);
    }
    if (data is List) {
      return _sanitizeValue(data, 0);
    }
    return data;
  }
}
