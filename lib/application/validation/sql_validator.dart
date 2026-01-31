import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class SqlValidator {
  SqlValidator._();

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
