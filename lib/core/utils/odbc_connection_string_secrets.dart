/// Utilities for extracting and removing ODBC credentials embedded in
/// connection strings (`PWD` / `PASSWORD` segments).
class OdbcConnectionStringSecrets {
  OdbcConnectionStringSecrets._();

  static final RegExp _connectionSecretSegment = RegExp(
    r'(?:^|;)\s*(?:pwd|password)\s*=\s*[^;]*',
    caseSensitive: false,
  );

  static final RegExp _connectionSecretCapture = RegExp(
    r'(?:^|;)\s*(?:pwd|password)\s*=\s*([^;]*)',
    caseSensitive: false,
  );

  static final RegExp _duplicateSemicolons = RegExp(';{2,}');
  static final RegExp _leadingOrTrailingSemicolons = RegExp(r'^;+|;+$');

  /// Returns the password value from [connectionString], or null when absent.
  static String? extractPasswordFromConnectionString(String connectionString) {
    final match = _connectionSecretCapture.firstMatch(connectionString);
    final value = match?.group(1)?.trim();
    if (value == null || value.isEmpty) {
      return null;
    }
    return value;
  }

  /// Appends a `PWD` segment when [connectionString] has no embedded password.
  static String injectPasswordIntoConnectionString(
    String connectionString,
    String password,
  ) {
    final trimmedPassword = password.trim();
    if (connectionString.isEmpty || trimmedPassword.isEmpty) {
      return connectionString;
    }
    if (extractPasswordFromConnectionString(connectionString) != null) {
      return connectionString;
    }

    final separator = connectionString.endsWith(';') ? '' : ';';
    return '$connectionString${separator}PWD=$trimmedPassword';
  }

  /// Returns [connectionString] with every `PWD` / `PASSWORD` segment removed.
  static String stripPasswordFromConnectionString(String connectionString) {
    if (connectionString.isEmpty) {
      return connectionString;
    }

    final stripped = connectionString
        .replaceAll(_connectionSecretSegment, '')
        .replaceAll(_duplicateSemicolons, ';')
        .replaceAll(_leadingOrTrailingSemicolons, '');
    return stripped;
  }
}
