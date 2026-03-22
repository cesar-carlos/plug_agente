/// Shared `.env` line parser for E2E tooling and `test/helpers/e2e_env.dart`.
///
/// Rules (aligned across `tool/check_e2e_env.dart` and `test/helpers/e2e_env.dart`):
/// - One `key=value` per line; first `=` separates key from value.
/// - Empty lines and lines starting with `#` are ignored.
/// - Leading/trailing whitespace is trimmed on key and value.
/// - Optional surrounding single or double quotes on the value are stripped.
Map<String, String> parseDotEnvContent(String content) {
  final result = <String, String>{};
  for (final line in content.split(RegExp(r'\r?\n'))) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    final idx = trimmed.indexOf('=');
    if (idx <= 0) continue;
    final key = trimmed.substring(0, idx).trim();
    var value = trimmed.substring(idx + 1).trim();
    final isDoubleQuoted =
        value.startsWith('"') && value.endsWith('"') && value.length >= 2;
    final isSingleQuoted =
        value.startsWith("'") && value.endsWith("'") && value.length >= 2;
    if (isDoubleQuoted) {
      value = value.substring(1, value.length - 1);
    } else if (isSingleQuoted) {
      value = value.substring(1, value.length - 1);
    } else {
      value = _stripInlineNote(value);
    }
    result[key] = value;
  }
  return result;
}

String _stripInlineNote(String value) {
  const markers = <String>[
    ' #',
    ' \u2013 ',
    ' \u2014 ',
  ];
  var cutIndex = value.length;
  for (final marker in markers) {
    final idx = value.indexOf(marker);
    if (idx >= 0 && idx < cutIndex) {
      cutIndex = idx;
    }
  }
  if (cutIndex == value.length) {
    return value;
  }
  return value.substring(0, cutIndex).trimRight();
}
