import 'dart:convert';

/// Reads JWT payload claims without signature verification (client-side scheduling only).
abstract final class JwtPayloadReader {
  /// JWT `exp` claim in seconds since epoch, or null when not decodable.
  static int? expiryEpochSeconds(String? token) {
    final trimmed = token?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    final parts = trimmed.split('.');
    if (parts.length < 2) {
      return null;
    }
    try {
      var payloadSegment = parts[1];
      final padding = (4 - payloadSegment.length % 4) % 4;
      if (padding > 0) {
        payloadSegment = '$payloadSegment${'=' * padding}';
      }
      final decoded = utf8.decode(base64Url.decode(payloadSegment));
      final Object? parsed = jsonDecode(decoded);
      if (parsed is! Map<String, Object?>) {
        return null;
      }
      final exp = parsed['exp'];
      if (exp is int) {
        return exp;
      }
      if (exp is num) {
        return exp.toInt();
      }
      return null;
    } on Object {
      return null;
    }
  }

  /// Delay until proactive refresh should run (refresh [margin] before `exp`).
  ///
  /// Returns [Duration.zero] when the token is already inside the margin or
  /// expired. Returns null when `exp` cannot be read.
  static Duration? delayUntilProactiveRefresh({
    required String accessToken,
    required Duration margin,
    DateTime? now,
  }) {
    final exp = expiryEpochSeconds(accessToken);
    if (exp == null) {
      return null;
    }
    final nowSeconds = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch ~/ 1000;
    final refreshAtSeconds = exp - margin.inSeconds;
    final delaySeconds = refreshAtSeconds - nowSeconds;
    if (delaySeconds <= 0) {
      return Duration.zero;
    }
    return Duration(seconds: delaySeconds);
  }
}
