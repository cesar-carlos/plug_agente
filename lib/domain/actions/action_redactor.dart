class AgentActionRedactor {
  const AgentActionRedactor({
    this.replacement = '[REDACTED]',
  });

  final String replacement;

  static final RegExp _secretPlaceholderPattern = RegExp(
    r'\$\{secret:[^}]+\}',
    caseSensitive: false,
  );

  static final RegExp _keyValueSecretPattern = RegExp(
    r'''\b(password|passwd|senha|secret|token|api[_-]?key)\s*=\s*("([^"]*)"|'([^']*)'|[^\s|&<>]+)''',
    caseSensitive: false,
  );

  static final RegExp _argumentSecretPattern = RegExp(
    r'''(--?(?:password|passwd|senha|secret|token|api[_-]?key)\s+)("([^"]*)"|'([^']*)'|[^\s|&<>]+)''',
    caseSensitive: false,
  );

  /// Redacts common Data7.Config XML credential elements when config snippets leak into logs.
  static final RegExp _xmlSensitiveElementPattern = RegExp(
    r'<(Senha|Usuario|Password|passwd|Servidor|BaseDados)(?:\s[^>]*)?>[^<]*</\1>',
    caseSensitive: false,
  );

  String redactText(String value) {
    if (value.isEmpty) {
      return value;
    }

    return value
        .replaceAll(_secretPlaceholderPattern, replacement)
        .replaceAllMapped(_keyValueSecretPattern, (match) => '${match.group(1)}=$replacement')
        .replaceAllMapped(_argumentSecretPattern, (match) => '${match.group(1)}$replacement')
        .replaceAllMapped(
          _xmlSensitiveElementPattern,
          (match) => '<${match.group(1)}>$replacement</${match.group(1)}>',
        );
  }
}
