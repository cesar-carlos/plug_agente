import 'package:plug_agente/core/utils/split_sql_statements.dart';
import 'package:plug_agente/core/utils/sql_keyword_scan.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:result_dart/result_dart.dart';

/// Heuristic SQL classifier for client-token authorization (operation + table/view
/// names). It is not a full parser: nested SQL, some dialect-specific syntax,
/// and adversarial spacing may be misclassified; sensitive deployments should
/// pair this with hub-side validation and least-privilege ODBC credentials.
class SqlOperationClassification {
  const SqlOperationClassification({
    required this.operation,
    required this.resources,
  });

  final SqlOperation operation;
  final List<DatabaseResource> resources;
}

class SqlOperationClassifier {
  static final RegExp _blockComments = RegExp(r'/\*.*?\*/', dotAll: true);
  static final RegExp _lineComments = RegExp(r'--.*$', multiLine: true);
  static final RegExp _identifierStart = RegExp('[a-z_]', caseSensitive: false);
  static final RegExp _identifierPart = RegExp(
    r'[a-z0-9_$#]',
    caseSensitive: false,
  );

  Result<SqlOperationClassification> classify(String sql) {
    final trimmed = sql.trim();
    if (trimmed.isEmpty) {
      return Failure(domain.ValidationFailure('SQL cannot be empty'));
    }

    if (sqlHasMultipleTopLevelStatements(trimmed)) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Multiple SQL statements are not supported',
          context: {
            'operation': 'sql_classification',
          },
        ),
      );
    }

    final normalized = _normalizeSql(sql);
    if (normalized.isEmpty) {
      return Failure(domain.ValidationFailure('SQL cannot be empty'));
    }

    final operation = _detectOperation(normalized);
    if (operation == null) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Unsupported SQL operation',
          context: {
            'operation': 'sql_classification',
          },
        ),
      );
    }

    final resources = _extractResources(normalized, operation);
    if (resources.isEmpty) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Unable to determine SQL target resources',
          context: {
            'operation': 'sql_classification',
          },
        ),
      );
    }

    return Success(
      SqlOperationClassification(
        operation: operation,
        resources: resources,
      ),
    );
  }

  SqlOperation? _detectOperation(String sql) {
    if (sql.startsWith('select ') || sql.startsWith('with ')) {
      return SqlOperation.read;
    }
    if (sql.startsWith('update ') || sql.startsWith('insert ') || sql.startsWith('merge ')) {
      return SqlOperation.update;
    }
    if (sql.startsWith('delete ')) {
      return SqlOperation.delete;
    }
    return null;
  }

  List<DatabaseResource> _extractResources(
    String sql,
    SqlOperation operation,
  ) {
    final resources = <DatabaseResource>{};
    final cteAliases = _extractCteAliases(sql);

    if (operation == SqlOperation.read) {
      resources.addAll(_extractByKeywords(sql, const ['from', 'join']));
    } else if (operation == SqlOperation.update) {
      if (sql.startsWith('update ')) {
        final updateTarget = _extractUpdateTarget(sql);
        if (updateTarget != null) {
          resources.add(
            DatabaseResource(
              resourceType: DatabaseResourceType.unknown,
              name: updateTarget,
            ),
          );
        }
        resources.addAll(_extractByKeywords(sql, const ['from', 'join']));
      } else if (sql.startsWith('insert ')) {
        resources.addAll(_extractByKeywords(sql, const ['into']));
      } else if (sql.startsWith('merge ')) {
        resources.addAll(_extractByKeywords(sql, const ['merge', 'into']));
      }
    } else if (operation == SqlOperation.delete) {
      resources.addAll(_extractByKeywords(sql, const ['from']));
    }

    return resources.where((resource) => !_isCteAliasReference(resource, cteAliases)).toList();
  }

  Set<DatabaseResource> _extractByKeywords(
    String sql,
    List<String> keywords,
  ) {
    final extracted = <DatabaseResource>{};
    final lowerSql = sql.toLowerCase();

    for (final keyword in keywords) {
      var searchIndex = 0;
      while (searchIndex < sql.length) {
        final keywordIndex = findSqlKeyword(lowerSql, keyword, searchIndex);
        if (keywordIndex < 0) {
          break;
        }
        searchIndex = keywordIndex + keyword.length;
        final identifier = _readQualifiedIdentifier(sql, searchIndex);
        if (identifier == null || identifier.value.trim().isEmpty) {
          continue;
        }
        extracted.add(
          DatabaseResource(
            resourceType: DatabaseResourceType.unknown,
            name: identifier.value,
          ),
        );
      }
    }

    return extracted;
  }

  String? _extractUpdateTarget(String sql) {
    final lowerSql = sql.toLowerCase();
    final updateIndex = findSqlKeyword(lowerSql, 'update', 0);
    if (updateIndex < 0) {
      return null;
    }
    final parsed = _readQualifiedIdentifier(sql, updateIndex + 'update'.length);
    if (parsed == null) {
      return null;
    }

    final hasFromClause =
        findSqlKeyword(lowerSql, 'from', parsed.nextIndex) >= 0 ||
            findSqlKeyword(lowerSql, 'join', parsed.nextIndex) >= 0;
    if (hasFromClause && _looksLikeAlias(parsed.value)) {
      return null;
    }
    return parsed.value;
  }

  bool _looksLikeAlias(String identifier) {
    final trimmed = identifier.trim();
    if (trimmed.isEmpty) {
      return false;
    }
    if (trimmed.contains('.')) {
      return false;
    }
    return !trimmed.startsWith('[') && !trimmed.startsWith('"') && !trimmed.startsWith('`');
  }

  Set<String> _extractCteAliases(String sql) {
    final aliases = <String>{};
    final lowerSql = sql.toLowerCase();
    var index = _skipWhitespace(sql, 0);
    if (!sqlIsKeywordAt(lowerSql, 'with', index)) {
      return aliases;
    }
    index = _skipWhitespace(sql, index + 4);

    if (sqlIsKeywordAt(lowerSql, 'recursive', index)) {
      index = _skipWhitespace(sql, index + 9);
    }

    while (index < sql.length) {
      final parsedName = _readQualifiedIdentifier(sql, index);
      if (parsedName == null) {
        break;
      }
      final normalizedAlias = DatabaseResource(
        resourceType: DatabaseResourceType.unknown,
        name: parsedName.value,
      ).normalizedName;
      aliases.add(normalizedAlias);
      index = _skipWhitespace(sql, parsedName.nextIndex);

      if (index < sql.length && sql[index] == '(') {
        final closeColumnList = _findClosingParenthesis(sql, index);
        if (closeColumnList < 0) {
          break;
        }
        index = _skipWhitespace(sql, closeColumnList + 1);
      }

      if (!sqlIsKeywordAt(lowerSql, 'as', index)) {
        break;
      }
      index = _skipWhitespace(sql, index + 2);
      if (index >= sql.length || sql[index] != '(') {
        break;
      }
      final closeBody = _findClosingParenthesis(sql, index);
      if (closeBody < 0) {
        break;
      }
      index = _skipWhitespace(sql, closeBody + 1);
      if (index >= sql.length || sql[index] != ',') {
        break;
      }
      index = _skipWhitespace(sql, index + 1);
    }

    return aliases;
  }

  bool _isCteAliasReference(DatabaseResource resource, Set<String> cteAliases) {
    if (cteAliases.isEmpty) {
      return false;
    }
    final normalized = resource.normalizedName;
    if (cteAliases.contains(normalized)) {
      return true;
    }
    final parts = normalized.split('.');
    return parts.isNotEmpty && cteAliases.contains(parts.last);
  }

  _ParsedIdentifier? _readQualifiedIdentifier(String sql, int start) {
    var index = _skipWhitespace(sql, start);
    if (index >= sql.length || sql[index] == '(') {
      return null;
    }

    final firstSegment = _readIdentifierSegment(sql, index);
    if (firstSegment == null) {
      return null;
    }

    final buffer = StringBuffer(firstSegment.value);
    index = firstSegment.nextIndex;
    while (true) {
      index = _skipWhitespace(sql, index);
      if (index >= sql.length || sql[index] != '.') {
        break;
      }
      buffer.write('.');
      index = _skipWhitespace(sql, index + 1);
      final nextSegment = _readIdentifierSegment(sql, index);
      if (nextSegment == null) {
        break;
      }
      buffer.write(nextSegment.value);
      index = nextSegment.nextIndex;
    }

    return _ParsedIdentifier(
      value: buffer.toString(),
      nextIndex: index,
    );
  }

  _ParsedIdentifier? _readIdentifierSegment(String sql, int start) {
    if (start >= sql.length) {
      return null;
    }

    final current = sql[start];
    if (current == '[') {
      final closeIndex = sql.indexOf(']', start + 1);
      if (closeIndex < 0) {
        return null;
      }
      return _ParsedIdentifier(
        value: sql.substring(start, closeIndex + 1),
        nextIndex: closeIndex + 1,
      );
    }
    if (current == '"' || current == '`') {
      final closeIndex = sql.indexOf(current, start + 1);
      if (closeIndex < 0) {
        return null;
      }
      return _ParsedIdentifier(
        value: sql.substring(start, closeIndex + 1),
        nextIndex: closeIndex + 1,
      );
    }
    if (!_isIdentifierStart(current)) {
      return null;
    }
    var index = start + 1;
    while (index < sql.length && _isIdentifierPart(sql[index])) {
      index++;
    }
    return _ParsedIdentifier(
      value: sql.substring(start, index),
      nextIndex: index,
    );
  }

  int _skipWhitespace(String sql, int start) {
    var index = start;
    while (index < sql.length && sql[index].trim().isEmpty) {
      index++;
    }
    return index;
  }

  bool _isIdentifierStart(String char) {
    return _identifierStart.hasMatch(char);
  }

  bool _isIdentifierPart(String char) {
    return _identifierPart.hasMatch(char);
  }

  int _findClosingParenthesis(String sql, int openIndex) {
    var depth = 0;
    var inSingleQuote = false;
    var inDoubleQuote = false;
    var inBracketQuote = false;
    for (var i = openIndex; i < sql.length; i++) {
      final char = sql[i];
      if (!inDoubleQuote && !inBracketQuote && char == "'") {
        inSingleQuote = !inSingleQuote;
        continue;
      }
      if (!inSingleQuote && !inBracketQuote && char == '"') {
        inDoubleQuote = !inDoubleQuote;
        continue;
      }
      if (!inSingleQuote && !inDoubleQuote && char == '[') {
        inBracketQuote = true;
        continue;
      }
      if (inBracketQuote && char == ']') {
        inBracketQuote = false;
        continue;
      }
      if (inSingleQuote || inDoubleQuote || inBracketQuote) {
        continue;
      }
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
    }
    return -1;
  }

  String _normalizeSql(String sql) {
    final noBlockComments = sql.replaceAll(_blockComments, ' ');
    final noLineComments = noBlockComments.replaceAll(_lineComments, ' ');
    return noLineComments.trim().toLowerCase();
  }
}

class _ParsedIdentifier {
  const _ParsedIdentifier({
    required this.value,
    required this.nextIndex,
  });

  final String value;
  final int nextIndex;
}
