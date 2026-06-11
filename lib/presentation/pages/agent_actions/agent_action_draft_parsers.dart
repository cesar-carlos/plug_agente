import 'dart:convert';

/// Pure parsing/formatting helpers for the agent action editor draft inputs.
///
/// Extracted from the editor state so the text-to-domain conversions live in a
/// single, side-effect-free, independently testable place. UI/state concerns
/// (validation messages, `setState`, controllers) stay in the editor.
abstract final class AgentActionDraftParsers {
  AgentActionDraftParsers._();

  /// Parses a strictly positive integer, returning `null` when invalid.
  static int? positiveInt(String input) {
    final parsed = int.tryParse(input.trim());
    if (parsed == null || parsed < 1) {
      return null;
    }
    return parsed;
  }

  /// Splits a comma-separated list into a set of non-empty trimmed tokens.
  static Set<String> commaSeparatedTokens(String input) {
    if (input.trim().isEmpty) {
      return const <String>{};
    }
    return input.split(',').map((String part) => part.trim()).where((String part) => part.isNotEmpty).toSet();
  }

  /// Parses `NAME=value` lines into a map. Blank and `#`-prefixed lines are
  /// ignored. Throws [FormatException] when a line lacks a valid name.
  static Map<String, String> environmentVariables(String input) {
    final variables = <String, String>{};
    for (final rawLine in input.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty || line.startsWith('#')) {
        continue;
      }

      final separatorIndex = line.indexOf('=');
      if (separatorIndex <= 0) {
        throw const FormatException('Invalid environment variable line.');
      }

      final name = line.substring(0, separatorIndex).trim();
      if (name.isEmpty) {
        throw const FormatException('Environment variable name is blank.');
      }

      variables[name] = line.substring(separatorIndex + 1);
    }

    return Map<String, String>.unmodifiable(variables);
  }

  /// Renders environment variables as sorted `NAME=value` lines.
  static String formatEnvironmentVariables(Map<String, String> variables) {
    if (variables.isEmpty) {
      return '';
    }
    final names = variables.keys.toList()..sort();
    return names.map((String name) => '$name=${variables[name]}').join('\n');
  }

  /// Parses accepted exit codes. Empty input defaults to `{0}`; returns `null`
  /// when any token is not an integer.
  static Set<int>? acceptedExitCodes(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const <int>{0};
    }

    final codes = <int>{};
    for (final part in trimmed.split(',')) {
      final token = part.trim();
      if (token.isEmpty) {
        continue;
      }
      final code = int.tryParse(token);
      if (code == null) {
        return null;
      }
      codes.add(code);
    }

    if (codes.isEmpty) {
      return const <int>{0};
    }

    return codes;
  }

  /// Parses a JSON object of COM arguments. Empty input yields an empty map;
  /// returns `null` when the JSON is invalid or not an object.
  static Map<String, Object?>? comObjectArguments(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) {
      return const <String, Object?>{};
    }

    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map) {
        return null;
      }
      return Map<String, Object?>.from(decoded);
    } on FormatException {
      return null;
    }
  }

  /// Splits multi-line input into a list of non-empty trimmed arguments.
  static List<String> structuredArguments(String raw) {
    return raw
        .split(RegExp(r'\r?\n'))
        .map((String line) => line.trim())
        .where((String line) => line.isNotEmpty)
        .toList(growable: false);
  }

  /// Normalizes a Windows path for case-insensitive separator-agnostic compares.
  static String normalizePathForComparison(String path) {
    return path.trim().replaceAll('/', r'\').toLowerCase();
  }

  /// Whether a normalized path ends with (or equals) the given file name.
  static bool endsWithFileName(String normalizedPath, String fileName) {
    final expectedSuffix = r'\' + fileName.toLowerCase();
    return normalizedPath.endsWith(expectedSuffix) || normalizedPath == fileName.toLowerCase();
  }
}
