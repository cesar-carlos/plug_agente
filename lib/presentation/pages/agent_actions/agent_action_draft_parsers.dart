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

  static Duration? positiveDuration(String input, {required bool seconds}) {
    final raw = input.trim().replaceAll(',', '.');
    if (!RegExp(r'^\d+(?:\.\d+)?$').hasMatch(raw)) return null;
    final value = double.tryParse(raw);
    if (value == null || !value.isFinite || value <= 0) return null;
    final milliseconds = value * (seconds ? 1000 : 60000);
    if (!milliseconds.isFinite || milliseconds > 86400000000) return null;
    final rounded = milliseconds.round();
    return rounded > 0 ? Duration(milliseconds: rounded) : null;
  }

  static String formatDuration(Duration duration, {required bool seconds}) {
    final divisor = seconds ? 1000 : 60000;
    if (duration.inMilliseconds % divisor == 0) return '${duration.inMilliseconds ~/ divisor}';
    return (duration.inMilliseconds / divisor).toString();
  }

  static int? timeOfDayMinutes(String input) {
    final match = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(input.trim());
    if (match == null) return null;
    final hour = int.parse(match[1]!);
    final minute = int.parse(match[2]!);
    return hour < 24 && minute < 60 ? hour * 60 + minute : null;
  }

  static String formatTimeOfDay(int? minutes) => minutes == null
      ? ''
      : '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

  /// Parses a non-negative integer, returning `null` when invalid.
  static int? nonNegativeInt(String input) {
    final parsed = int.tryParse(input.trim());
    if (parsed == null || parsed < 0) {
      return null;
    }
    return parsed;
  }

  /// Splits a comma-separated list into a set of non-empty trimmed tokens.
  static Set<String> commaSeparatedTokens(String input) {
    if (input.trim().isEmpty) {
      return const <String>{};
    }
    return input.split(',').map((part) => part.trim()).where((part) => part.isNotEmpty).toSet();
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
    return names.map((name) => '$name=${variables[name]}').join('\n');
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
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
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
