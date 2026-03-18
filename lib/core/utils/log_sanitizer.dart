/// Sanitizes sensitive data from logs and serialized payloads.
class LogSanitizer {
  LogSanitizer._();

  static const _sensitiveKeys = {
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
    'bearer',
  };

  static const _redacted = '[REDACTED]';

  static bool _isSensitiveKey(String key) {
    final lower = key.toLowerCase();
    if (_sensitiveKeys.contains(lower)) return true;
    return _sensitiveKeys.any(lower.contains);
  }

  /// Recursively sanitizes a map, replacing sensitive values.
  static Map<String, dynamic> sanitizeMap(Map<String, dynamic> map) {
    return map.map((key, value) {
      if (_isSensitiveKey(key)) {
        return MapEntry(key, _redacted);
      }
      if (value is Map<String, dynamic>) {
        return MapEntry(key, sanitizeMap(value));
      }
      if (value is Map) {
        return MapEntry(
          key,
          sanitizeMap(Map<String, dynamic>.from(value)),
        );
      }
      if (value is List) {
        return MapEntry(
          key,
          value.map((e) => e is Map ? sanitizeMap(Map<String, dynamic>.from(e)) : e).toList(),
        );
      }
      return MapEntry(key, value);
    });
  }

  /// Sanitizes parameters for query logging.
  static Map<String, dynamic>? sanitizeParameters(Map<String, dynamic>? params) {
    if (params == null || params.isEmpty) return params;
    return sanitizeMap(Map<String, dynamic>.from(params));
  }

  /// Sanitizes dynamic data (map, list, or other) for display.
  static dynamic sanitize(dynamic data) {
    if (data is Map) {
      return sanitizeMap(Map<String, dynamic>.from(data));
    }
    if (data is List) {
      return data.map((e) => e is Map ? sanitizeMap(Map<String, dynamic>.from(e)) : e).toList();
    }
    return data;
  }
}
