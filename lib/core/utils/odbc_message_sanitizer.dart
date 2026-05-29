/// Redacts credential tokens that ODBC drivers occasionally echo back inside
/// error messages (e.g. connection-string fragments) before such text crosses
/// the RPC boundary toward the hub.
///
/// This is intentionally conservative: it only rewrites recognizable
/// `KEY=value` credential pairs (passwords) and leaves the rest of the
/// diagnostic text intact so the message stays useful.
class OdbcMessageSanitizer {
  OdbcMessageSanitizer._();

  static const String _redacted = '***';

  static final RegExp _credentialToken = RegExp(
    r'(pwd|password)\s*=\s*[^;]*',
    caseSensitive: false,
  );

  /// Returns [message] with credential tokens redacted.
  static String sanitize(String message) {
    if (message.isEmpty) {
      return message;
    }
    return message.replaceAllMapped(
      _credentialToken,
      (match) => '${match.group(1)}=$_redacted',
    );
  }

  /// Null-safe variant for optional message fields.
  static String? sanitizeNullable(String? message) {
    if (message == null) {
      return null;
    }
    return sanitize(message);
  }
}
