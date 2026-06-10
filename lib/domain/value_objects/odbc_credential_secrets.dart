class OdbcCredentialSecrets {
  const OdbcCredentialSecrets({this.password});

  final String? password;

  bool get hasAny => password?.trim().isNotEmpty ?? false;

  OdbcCredentialSecrets mergeMissingFrom(OdbcCredentialSecrets fallback) {
    return OdbcCredentialSecrets(
      password: _normalize(password) ?? _normalize(fallback.password),
    );
  }

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
