import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/core/utils/split_sql_statements.dart';
import 'package:plug_agente/core/utils/sql_dangerous_pattern_scan.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

class SqlPaginationPlan {
  const SqlPaginationPlan({
    required this.queryFingerprint,
    required this.orderBy,
  });

  final String queryFingerprint;
  final List<QueryPaginationOrderTerm> orderBy;
}

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

  static final RegExp _normalizeFingerprintWhitespace = RegExp(r'\s+');
  static final RegExp _wordBoundaryChar = RegExp(
    '[a-z0-9_]',
    caseSensitive: false,
  );

  static final RegExp _trailingSemicolons = RegExp(r';+\s*$');
  static final RegExp _namedParameter = RegExp(r':(\w+)');
  static final RegExp _removeCommentsLine = RegExp(r'--.*?\n');
  static final RegExp _removeCommentsBlock = RegExp(
    r'/\*.*?\*/',
    dotAll: true,
  );
  static final RegExp _orderTermPattern = RegExp(
    r'^(?<expr>(?:\[[^\]]+\]|"[^"]+"|[A-Za-z_][A-Za-z0-9_$]*)(?:\.(?:\[[^\]]+\]|"[^"]+"|[A-Za-z_][A-Za-z0-9_$]*))*)(?:\s+(?<dir>asc|desc))?$',
    caseSensitive: false,
  );

  /// Validates SQL for execution in RPC/legacy flows.
  /// Allows SELECT, WITH, UPDATE, INSERT, MERGE, DELETE.
  /// Blocks multiple statements, comments, and dangerous patterns.
  static Result<void> validateSqlForExecution(
    String query, {
    bool allowMultipleStatements = false,
  }) {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return Failure(
        _sqlValidationFailure(
          message: 'SQL cannot be empty',
          userMessage: 'A consulta SQL está vazia. Informe um comando SQL para continuar.',
        ),
      );
    }

    final normalized = trimmed.toLowerCase();
    if (!allowMultipleStatements && sqlHasMultipleTopLevelStatements(trimmed)) {
      return Failure(
        _sqlValidationFailure(
          message: 'Multiple SQL statements are not supported',
          userMessage: 'A consulta contém múltiplos comandos. Envie apenas um comando SQL por requisição.',
        ),
      );
    }

    final startsWithAllowed = _allowedPrefixes.any(normalized.startsWith);
    if (!startsWithAllowed) {
      return Failure(
        _sqlValidationFailure(
          message: 'Unsupported SQL operation. Allowed: SELECT, WITH, UPDATE, INSERT, MERGE, DELETE',
          userMessage: 'Operação SQL não suportada. Use apenas SELECT, WITH, UPDATE, INSERT, MERGE ou DELETE.',
        ),
      );
    }

    final dangerous = _checkDangerousPatterns(query);
    if (dangerous != null) {
      return Failure(dangerous);
    }

    return const Success(unit);
  }

  static bool containsMultipleStatements(String query) {
    return sqlHasMultipleTopLevelStatements(query.trim());
  }

  static domain.ValidationFailure? _checkDangerousPatterns(String query) {
    if (sqlContainsTopLevelDangerousPatterns(query)) {
      return _sqlValidationFailure(
        message: 'Query contains potentially dangerous patterns',
        userMessage:
            'A consulta foi bloqueada por conter padrões potencialmente perigosos. Revise o comando e tente novamente.',
      );
    }
    return null;
  }

  static Result<void> validateSelectQuery(String query) {
    final trimmed = query.trim().toUpperCase();

    if (!trimmed.startsWith('SELECT') && !trimmed.startsWith('WITH')) {
      return Failure(
        _sqlValidationFailure(
          message: 'Apenas consultas SELECT/WITH são permitidas no playground',
          userMessage: 'Esta operação aceita apenas consultas SELECT ou WITH.',
        ),
      );
    }

    if (sqlContainsTopLevelDangerousPatterns(query)) {
      return Failure(
        _sqlValidationFailure(
          message: 'Query contém padrões potencialmente perigosos',
          userMessage:
              'A consulta foi bloqueada por conter padrões potencialmente perigosos. Revise o comando e tente novamente.',
        ),
      );
    }

    return const Success(unit);
  }

  static Result<SqlPaginationPlan> validatePaginationQuery(String query) {
    final selectValidation = validateSelectQuery(query);
    if (selectValidation.isError()) {
      return Failure(
        _sqlValidationFailure(
          message: 'Pagination is supported only for SELECT/WITH queries',
          userMessage: 'A paginação só pode ser usada com consultas SELECT ou WITH.',
        ),
      );
    }

    final normalizedQuery = query.trim().replaceFirst(_trailingSemicolons, '');
    final orderByIndex = _findTopLevelOrderBy(normalizedQuery);
    if (orderByIndex < 0) {
      return Failure(
        _sqlValidationFailure(
          message: 'Paginated queries must declare an explicit ORDER BY clause',
          userMessage: 'Para usar paginação, a consulta precisa declarar ORDER BY explícito.',
        ),
      );
    }

    final orderByClause = normalizedQuery.substring(orderByIndex + 8).trim();
    if (_containsTopLevelKeyword(orderByClause, 'offset') ||
        _containsTopLevelKeyword(orderByClause, 'fetch') ||
        _containsTopLevelKeyword(orderByClause, 'limit')) {
      return Failure(
        _sqlValidationFailure(
          message: 'Paginated queries cannot declare LIMIT/OFFSET/FETCH directly',
          userMessage:
              'A consulta paginada não pode usar LIMIT, OFFSET ou FETCH diretamente. Deixe a paginação para o options.page/page_size ou cursor.',
        ),
      );
    }

    final orderTerms = _splitTopLevelCommaSeparated(
      orderByClause,
    ).map(_parseOrderTerm).toList();
    if (orderTerms.any((term) => term == null)) {
      return Failure(
        _sqlValidationFailure(
          message: 'Pagination requires ORDER BY with simple column names or aliases',
          userMessage: 'A paginação exige ORDER BY com nomes de coluna ou aliases simples.',
        ),
      );
    }

    return Success(
      SqlPaginationPlan(
        queryFingerprint: sha256.convert(utf8.encode(_normalizeForFingerprint(normalizedQuery))).toString(),
        orderBy: orderTerms.whereType<QueryPaginationOrderTerm>().toList(),
      ),
    );
  }

  static bool containsTopLevelPaginationClause(String query) {
    final normalizedQuery = query.trim().replaceFirst(_trailingSemicolons, '');
    if (normalizedQuery.isEmpty) {
      return false;
    }

    return _containsTopLevelKeyword(normalizedQuery, 'limit') ||
        _containsTopLevelKeyword(normalizedQuery, 'offset') ||
        _containsTopLevelKeyword(normalizedQuery, 'fetch');
  }

  static String stripTopLevelOrderBy(String query) {
    final normalizedQuery = query.trim().replaceFirst(_trailingSemicolons, '');
    if (normalizedQuery.isEmpty) {
      return normalizedQuery;
    }

    final orderByIndex = _findTopLevelOrderBy(normalizedQuery);
    if (orderByIndex < 0) {
      return normalizedQuery;
    }

    return normalizedQuery.substring(0, orderByIndex).trimRight();
  }

  static List<String> extractNamedParameters(String query) {
    final matches = _namedParameter.allMatches(query);
    return matches.map((m) => m.group(1)!).toSet().toList();
  }

  static int countPlaceholders(String query) {
    return '?'.allMatches(query).length;
  }

  static String removeComments(String query) {
    var result = query.replaceAll(_removeCommentsLine, '');

    result = result.replaceAll(_removeCommentsBlock, '');

    result = result.replaceAll(_normalizeFingerprintWhitespace, ' ');

    return result;
  }

  static int _findTopLevelOrderBy(String sql) {
    final lower = sql.toLowerCase();
    var depth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inBracketQuote = false;

    for (var i = 0; i < lower.length - 7; i++) {
      final current = lower[i];
      if (!inDoubleQuote && !inBracketQuote && current == "'") {
        inSingleQuote = !inSingleQuote;
        continue;
      }
      if (!inSingleQuote && !inBracketQuote && current == '"') {
        inDoubleQuote = !inDoubleQuote;
        continue;
      }
      if (!inSingleQuote && !inDoubleQuote && current == '[') {
        inBracketQuote = true;
        continue;
      }
      if (inBracketQuote && current == ']') {
        inBracketQuote = false;
        continue;
      }
      if (inSingleQuote || inDoubleQuote || inBracketQuote) {
        continue;
      }
      if (current == '(') {
        depth++;
        continue;
      }
      if (current == ')') {
        depth--;
        continue;
      }
      if (depth == 0 &&
          lower.startsWith('order by', i) &&
          _isWordBoundary(lower, i - 1) &&
          _isWordBoundary(lower, i + 8)) {
        return i;
      }
    }

    return -1;
  }

  static bool _containsTopLevelKeyword(String sql, String keyword) {
    final lower = sql.toLowerCase();
    var depth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inBracketQuote = false;

    for (var i = 0; i <= lower.length - keyword.length; i++) {
      final current = lower[i];
      if (!inDoubleQuote && !inBracketQuote && current == "'") {
        inSingleQuote = !inSingleQuote;
        continue;
      }
      if (!inSingleQuote && !inBracketQuote && current == '"') {
        inDoubleQuote = !inDoubleQuote;
        continue;
      }
      if (!inSingleQuote && !inDoubleQuote && current == '[') {
        inBracketQuote = true;
        continue;
      }
      if (inBracketQuote && current == ']') {
        inBracketQuote = false;
        continue;
      }
      if (inSingleQuote || inDoubleQuote || inBracketQuote) {
        continue;
      }
      if (current == '(') {
        depth++;
        continue;
      }
      if (current == ')') {
        depth--;
        continue;
      }
      if (depth == 0 &&
          lower.startsWith(keyword, i) &&
          _isWordBoundary(lower, i - 1) &&
          _isWordBoundary(lower, i + keyword.length)) {
        return true;
      }
    }

    return false;
  }

  static List<String> _splitTopLevelCommaSeparated(String sql) {
    final parts = <String>[];
    final buffer = StringBuffer();
    var depth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inBracketQuote = false;

    for (var i = 0; i < sql.length; i++) {
      final current = sql[i];
      if (!inDoubleQuote && !inBracketQuote && current == "'") {
        inSingleQuote = !inSingleQuote;
      } else if (!inSingleQuote && !inBracketQuote && current == '"') {
        inDoubleQuote = !inDoubleQuote;
      } else if (!inSingleQuote && !inDoubleQuote && current == '[') {
        inBracketQuote = true;
      } else if (inBracketQuote && current == ']') {
        inBracketQuote = false;
      } else if (!inSingleQuote && !inDoubleQuote && !inBracketQuote) {
        if (current == '(') {
          depth++;
        } else if (current == ')') {
          depth--;
        } else if (current == ',' && depth == 0) {
          parts.add(buffer.toString().trim());
          buffer.clear();
          continue;
        }
      }
      buffer.write(current);
    }

    final last = buffer.toString().trim();
    if (last.isNotEmpty) {
      parts.add(last);
    }
    return parts;
  }

  static QueryPaginationOrderTerm? _parseOrderTerm(String rawTerm) {
    final match = _orderTermPattern.firstMatch(rawTerm.trim());
    if (match == null) {
      return null;
    }

    final expression = match.namedGroup('expr')!;
    final segments = expression.split('.');
    final lookupKey = _stripIdentifierQuoting(segments.last);
    return QueryPaginationOrderTerm(
      expression: expression,
      lookupKey: lookupKey,
      descending: (match.namedGroup('dir') ?? '').toLowerCase() == 'desc',
    );
  }

  static String _stripIdentifierQuoting(String value) {
    final trimmed = value.trim();
    if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    if (trimmed.startsWith('"') && trimmed.endsWith('"')) {
      return trimmed.substring(1, trimmed.length - 1);
    }
    return trimmed;
  }

  static bool _isWordBoundary(String value, int index) {
    if (index < 0 || index >= value.length) {
      return true;
    }
    final char = value[index];
    return !_wordBoundaryChar.hasMatch(char);
  }

  static String _normalizeForFingerprint(String query) {
    return query.replaceAll(_normalizeFingerprintWhitespace, ' ').trim().toLowerCase();
  }

  static domain.ValidationFailure _sqlValidationFailure({
    required String message,
    required String userMessage,
  }) {
    return domain.ValidationFailure.withContext(
      message: message,
      context: <String, dynamic>{
        'operation': 'sql_validation',
        'reason': 'sql_validation_failed',
        'user_message': userMessage,
      },
    );
  }
}
