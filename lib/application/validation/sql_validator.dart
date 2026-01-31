import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Validador de SQL para prevenir injection.
///
/// Valida queries e ajuda a construir queries seguras com parâmetros.
class SqlValidator {
  SqlValidator._();

  /// Valida se a query é uma SELECT segura (sem literais perigosos).
  static Result<void> validateSelectQuery(String query) {
    final trimmed = query.trim().toUpperCase();

    // Verificar se é SELECT
    if (!trimmed.startsWith('SELECT') && !trimmed.startsWith('WITH')) {
      return Failure(
        domain.ValidationFailure(
          'Apenas consultas SELECT/WITH são permitidas no playground',
        ),
      );
    }

    // Verificar por padrões perigosos
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

  /// Extrai parâmetros nomeados da query (ex: :id, :name).
  static List<String> extractNamedParameters(String query) {
    final regex = RegExp(r':(\w+)');
    final matches = regex.allMatches(query);
    return matches.map((m) => m.group(1)!).toSet().toList();
  }

  /// Conta quantos placeholders (?) existem na query.
  static int countPlaceholders(String query) {
    return '?'.allMatches(query).length;
  }

  /// Remove comentários SQL da query.
  static String removeComments(String query) {
    // Remove comentários de linha única (--)
    var result = query.replaceAll(RegExp(r'--.*?\n'), '');

    // Remove comentários de bloco (/* */)
    result = result.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');

    // Limpa espaços extras resultantes da remoção
    result = result.replaceAllMapped(RegExp(r'\s+'), (match) => ' ');

    return result;
  }
}
