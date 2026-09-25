import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/core/utils/prepared_sql.dart';
import 'package:plug_agente/core/utils/split_sql_statements.dart';
import 'package:plug_agente/core/utils/sql_dangerous_pattern_scan.dart';
import 'package:plug_agente/core/utils/strip_sql_comments.dart';
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
    'create ',
    'alter ',
    'drop ',
    'truncate ',
  ];

  static final RegExp _normalizeFingerprintWhitespace = RegExp(r'\s+');
  static final RegExp _wordBoundaryChar = RegExp(
    '[a-z0-9_]',
    caseSensitive: false,
  );

  static final RegExp _trailingSemicolons = RegExp(r';+\s*$');
  static final RegExp _namedParameter = RegExp(r':(\w+)');
  static final RegExp _orderTermPattern = RegExp(
    r'^(?<expr>(?:\[[^\]]+\]|"[^"]+"|[A-Za-z_][A-Za-z0-9_$]*)(?:\.(?:\[[^\]]+\]|"[^"]+"|[A-Za-z_][A-Za-z0-9_$]*))*)(?:\s+(?<dir>asc|desc))?$',
    caseSensitive: false,
  );
  static final RegExp _selectClauseTop = RegExp(
    r'^\s+(?:distinct\s+)?top\s*\(?\s*\d+\s*\)?\b',
    caseSensitive: false,
  );

  /// Validates SQL for execution in RPC/legacy flows.
  /// Allows SELECT, WITH, UPDATE, INSERT, MERGE, DELETE and DDL v1.
  /// Documentation comments (`--`, `/* */`) are stripped before the prefix and
  /// dangerous-pattern checks. Multiple statements and lock hints stay blocked.
  static Result<void> validateSqlForExecution(
    String query, {
    bool allowMultipleStatements = false,
  }) {
    return validatePreparedSql(
      PreparedSql.parse(query),
      allowMultipleStatements: allowMultipleStatements,
    );
  }

  /// Validates a previously prepared SQL request. Documentation comments are
  /// already stripped on [prepared]; the original SQL is not sent to ODBC here.
  static Result<void> validatePreparedSql(
    PreparedSql prepared, {
    bool allowMultipleStatements = false,
  }) {
    if (prepared.trimmed.isEmpty) {
      return Failure(_emptySqlFailure());
    }

    if (!allowMultipleStatements && prepared.hasMultipleStatements) {
      return Failure(
        _sqlValidationFailure(
          message: 'Multiple SQL statements are not supported',
          userMessage: 'A consulta contém múltiplos comandos. Envie apenas um comando SQL por requisição.',
        ),
      );
    }

    if (prepared.stripped.isEmpty) {
      return Failure(_emptySqlFailure());
    }

    final normalized = prepared.stripped.toLowerCase();
    final startsWithAllowed = _allowedPrefixes.any(normalized.startsWith);
    if (!startsWithAllowed) {
      return Failure(
        _sqlValidationFailure(
          message:
              'Unsupported SQL operation. Allowed: SELECT, WITH, UPDATE, INSERT, MERGE, DELETE, CREATE, ALTER, DROP, TRUNCATE',
          userMessage:
              'Operação SQL não suportada. Use apenas SELECT, WITH, UPDATE, INSERT, MERGE, DELETE, CREATE, ALTER, DROP ou TRUNCATE.',
        ),
      );
    }

    final dangerous = _checkDangerousPatterns(prepared.stripped);
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
    return validatePreparedSelectQuery(PreparedSql.parse(query));
  }

  static Result<void> validatePreparedSelectQuery(PreparedSql prepared) {
    final stripped = prepared.stripped;
    if (stripped.isEmpty) {
      return Failure(_emptySqlFailure());
    }

    final upper = stripped.toUpperCase();
    if (!upper.startsWith('SELECT') && !upper.startsWith('WITH')) {
      return Failure(
        _sqlValidationFailure(
          message: 'Apenas consultas SELECT/WITH são permitidas no playground',
          userMessage: 'Esta operação aceita apenas consultas SELECT ou WITH.',
        ),
      );
    }

    if (sqlContainsTopLevelDangerousPatterns(stripped)) {
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

  /// True only for a single read query: `SELECT` or `WITH ... SELECT`, without
  /// a top-level locking clause (`FOR UPDATE` / `FOR SHARE` / `FOR KEY SHARE` /
  /// `FOR NO KEY UPDATE`) and without a CTE whose main statement writes.
  static bool isReadOnlyQuery(String query) {
    final normalized = _sqlForClauseScan(query);
    if (normalized.isEmpty || sqlContainsTopLevelDangerousPatterns(normalized)) {
      return false;
    }

    final upper = normalized.toUpperCase();
    if (upper.startsWith('SELECT')) {
      return !_containsTopLevelLockingClause(normalized);
    }
    if (!upper.startsWith('WITH')) {
      return false;
    }

    final mainKeyword = _mainKeywordAfterCtes(normalized);
    if (mainKeyword != 'select') {
      return false;
    }
    return !_containsTopLevelLockingClause(normalized);
  }

  static Result<SqlPaginationPlan> validatePaginationQuery(String query) {
    final selectValidation = validateSelectQuery(query);
    if (selectValidation.isError()) {
      return Failure(selectValidation.exceptionOrNull()! as domain.ValidationFailure);
    }

    final normalizedQuery = _sqlForClauseScan(query);
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
    final normalizedQuery = _sqlForClauseScan(query);
    if (normalizedQuery.isEmpty) {
      return false;
    }

    return _containsTopLevelKeyword(normalizedQuery, 'limit') ||
        _containsTopLevelKeyword(normalizedQuery, 'offset') ||
        _containsTopLevelKeyword(normalizedQuery, 'fetch');
  }

  static bool containsTopLevelSelectTop(String query) {
    final normalizedQuery = _sqlForClauseScan(query);
    if (normalizedQuery.isEmpty) {
      return false;
    }

    final lower = normalizedQuery.toLowerCase();
    var depth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inBracketQuote = false;

    for (var i = 0; i <= lower.length - 6; i++) {
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
          lower.startsWith('select', i) &&
          _isWordBoundary(lower, i - 1) &&
          _isWordBoundary(lower, i + 6)) {
        final remainder = normalizedQuery.substring(i + 6);
        if (_selectClauseTop.hasMatch(remainder)) {
          return true;
        }
      }
    }

    return false;
  }

  static bool queryDeclaresServerSideRowLimit(String query) {
    return containsTopLevelPaginationClause(query) || containsTopLevelSelectTop(query);
  }

  static String stripTopLevelOrderBy(String query) {
    final normalizedQuery = _sqlForClauseScan(query);
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
    return stripTopLevelSqlComments(query).replaceAll(_normalizeFingerprintWhitespace, ' ');
  }

  static String _sqlWithoutComments(String query) {
    return stripTopLevelSqlComments(query.trim()).trim();
  }

  static String _sqlForClauseScan(String query) {
    return _sqlWithoutComments(query).replaceFirst(_trailingSemicolons, '');
  }

  static domain.ValidationFailure _emptySqlFailure() {
    return _sqlValidationFailure(
      message: 'SQL cannot be empty',
      userMessage: 'A consulta SQL está vazia. Informe um comando SQL para continuar.',
    );
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

  static bool _containsTopLevelLockingClause(String sql) {
    const clauses = <String>[
      'for update',
      'for share',
      'for key share',
      'for no key update',
    ];
    for (final clause in clauses) {
      if (_containsTopLevelKeyword(sql, clause)) {
        return true;
      }
    }
    return false;
  }

  static String? _mainKeywordAfterCtes(String sql) {
    final lower = sql.toLowerCase();
    var index = _skipSqlWhitespace(lower, 0);
    if (!_keywordAt(lower, index, 'with')) {
      return null;
    }
    index = _skipSqlWhitespace(lower, index + 4);
    if (_keywordAt(lower, index, 'recursive')) {
      index = _skipSqlWhitespace(lower, index + 9);
    }

    while (index < lower.length) {
      index = _skipSqlIdentifier(sql, index);
      index = _skipSqlWhitespace(lower, index);
      if (index < sql.length && sql[index] == '(') {
        final afterColumns = _skipBalancedSqlParens(sql, index);
        if (afterColumns < 0) {
          return null;
        }
        index = _skipSqlWhitespace(lower, afterColumns);
      }
      if (!_keywordAt(lower, index, 'as')) {
        return null;
      }
      index = _skipSqlWhitespace(lower, index + 2);
      if (index >= sql.length || sql[index] != '(') {
        return null;
      }
      final afterBody = _skipBalancedSqlParens(sql, index);
      if (afterBody < 0) {
        return null;
      }
      index = _skipSqlWhitespace(lower, afterBody);
      if (index < sql.length && sql[index] == ',') {
        index = _skipSqlWhitespace(lower, index + 1);
        continue;
      }
      break;
    }

    index = _skipSqlWhitespace(lower, index);
    return _readSqlKeyword(lower, index);
  }

  static bool _keywordAt(String lower, int index, String keyword) {
    if (index < 0 || index + keyword.length > lower.length) {
      return false;
    }
    if (!lower.startsWith(keyword, index)) {
      return false;
    }
    return _isWordBoundary(lower, index - 1) && _isWordBoundary(lower, index + keyword.length);
  }

  static int _skipSqlWhitespace(String sql, int index) {
    var cursor = index;
    while (cursor < sql.length) {
      final char = sql[cursor];
      if (char != ' ' && char != '\t' && char != '\n' && char != '\r') {
        break;
      }
      cursor++;
    }
    return cursor;
  }

  static int _skipSqlIdentifier(String sql, int index) {
    if (index >= sql.length) {
      return index;
    }
    final start = sql[index];
    if (start == '[' || start == '"') {
      final end = start == '[' ? ']' : '"';
      final close = sql.indexOf(end, index + 1);
      return close < 0 ? sql.length : close + 1;
    }
    var cursor = index;
    while (cursor < sql.length && _wordBoundaryChar.hasMatch(sql[cursor])) {
      cursor++;
    }
    return cursor;
  }

  static int _skipBalancedSqlParens(String sql, int openIndex) {
    var depth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inBracketQuote = false;
    for (var i = openIndex; i < sql.length; i++) {
      final current = sql[i];
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
        if (depth == 0) {
          return i + 1;
        }
      }
    }
    return -1;
  }

  static String? _readSqlKeyword(String lower, int index) {
    if (index >= lower.length || !_isAsciiLetter(lower.codeUnitAt(index))) {
      return null;
    }
    var cursor = index;
    while (cursor < lower.length && _wordBoundaryChar.hasMatch(lower[cursor])) {
      cursor++;
    }
    return lower.substring(index, cursor);
  }

  static bool _isAsciiLetter(int codeUnit) =>
      (codeUnit >= 0x41 && codeUnit <= 0x5a) || (codeUnit >= 0x61 && codeUnit <= 0x7a);

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
        'reason': SqlPipelineContextConstants.sqlValidationFailedReason,
        'user_message': userMessage,
      },
    );
  }
}
