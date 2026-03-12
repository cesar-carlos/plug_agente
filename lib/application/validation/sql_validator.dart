import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class SqlValidator {
  SqlValidator._();

  static const _allowedPrefixes = [
    'select ',
    'with ',
    'update ',
    'insert ',
    'merge ',
    'delete ',
  ];

  static const _dangerousAfterSemicolon = [
    'drop',
    'delete',
    'insert',
    'update',
    'alter',
    'create',
    'truncate',
  ];

  /// Validates SQL for execution in RPC/legacy flows.
  /// Allows SELECT, WITH, UPDATE, INSERT, MERGE, DELETE.
  /// Blocks multiple statements, comments, and dangerous patterns.
  static Result<void> validateSqlForExecution(String query) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return Failure(
        domain.ValidationFailure('SQL cannot be empty'),
      );
    }

    final normalized = trimmed.toLowerCase();
    if (_containsMultipleStatements(normalized)) {
      return Failure(
        domain.ValidationFailure(
          'Multiple SQL statements are not supported',
        ),
      );
    }

    final startsWithAllowed = _allowedPrefixes.any(normalized.startsWith);
    if (!startsWithAllowed) {
      return Failure(
        domain.ValidationFailure(
          'Unsupported SQL operation. Allowed: SELECT, WITH, UPDATE, INSERT, MERGE, DELETE',
        ),
      );
    }

    final dangerous = _checkDangerousPatterns(query);
    if (dangerous != null) {
      return Failure(dangerous);
    }

    return const Success(unit);
  }

  static bool _containsMultipleStatements(String sql) {
    final withoutTrailing = sql.trim().replaceFirst(RegExp(r';$'), '');
    return withoutTrailing.contains(';');
  }

  static domain.ValidationFailure? _checkDangerousPatterns(String query) {
    if (RegExp('--', caseSensitive: false).hasMatch(query)) {
      return domain.ValidationFailure(
        'Query contains potentially dangerous patterns',
      );
    }
    if (RegExp(r'/\*', caseSensitive: false).hasMatch(query)) {
      return domain.ValidationFailure(
        'Query contains potentially dangerous patterns',
      );
    }
    final multiStmtPattern = RegExp(
      ';\\s*(${_dangerousAfterSemicolon.join('|')})',
      caseSensitive: false,
    );
    if (multiStmtPattern.hasMatch(query)) {
      return domain.ValidationFailure(
        'Query contains potentially dangerous patterns',
      );
    }
    return null;
  }

  static Result<void> validateSelectQuery(String query) {
    final trimmed = query.trim().toUpperCase();

    if (!trimmed.startsWith('SELECT') && !trimmed.startsWith('WITH')) {
      return Failure(
        domain.ValidationFailure(
          'Apenas consultas SELECT/WITH são permitidas no playground',
        ),
      );
    }

    final dangerousPatterns = [
      RegExp('--', caseSensitive: false),
      RegExp(r'/\*', caseSensitive: false),
      RegExp(
        r';\s*(DROP|DELETE|INSERT|UPDATE|ALTER|CREATE|TRUNCATE)',
        caseSensitive: false,
      ),
    ];

    for (final pattern in dangerousPatterns) {
      if (pattern.hasMatch(query)) {
        return Failure(
          domain.ValidationFailure(
            'Query contém padrões potencialmente perigosos',
          ),
        );
      }
    }

    return const Success(unit);
  }

  static List<String> extractNamedParameters(String query) {
    final regex = RegExp(r':(\w+)');
    final matches = regex.allMatches(query);
    return matches.map((m) => m.group(1)!).toSet().toList();
  }

  static int countPlaceholders(String query) {
    return '?'.allMatches(query).length;
  }

  static String removeComments(String query) {
    var result = query.replaceAll(RegExp(r'--.*?\n'), '');

    result = result.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

    result = result.replaceAllMapped(RegExp(r'\s+'), (match) => ' ');

    return result;
  }
}
