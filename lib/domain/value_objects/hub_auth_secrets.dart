class HubAuthSecrets {
  const HubAuthSecrets({
    this.authToken,
    this.refreshToken,
    this.authPassword,
  });

  final String? authToken;
  final String? refreshToken;
  final String? authPassword;

  bool get hasAny =>
      (authToken?.trim().isNotEmpty ?? false) ||
      (refreshToken?.trim().isNotEmpty ?? false) ||
      (authPassword?.trim().isNotEmpty ?? false);

  HubAuthSecrets mergeMissingFrom(HubAuthSecrets fallback) {
    return HubAuthSecrets(
      authToken: _normalize(authToken) ?? _normalize(fallback.authToken),
      refreshToken: _normalize(refreshToken) ?? _normalize(fallback.refreshToken),
      authPassword: _normalize(authPassword) ?? _normalize(fallback.authPassword),
    );
  }

  static String? _normalize(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }
}
