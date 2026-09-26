import 'package:meta/meta.dart';
import 'package:plug_agente/core/utils/prepared_sql.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:result_dart/result_dart.dart';

@immutable
class ClassifiedSqlResource {
  const ClassifiedSqlResource({
    required this.resource,
    required this.operation,
  });

  final DatabaseResource resource;
  final SqlOperation operation;

  String get normalizedName => resource.normalizedName;

  DatabaseResourceType get resourceType => resource.resourceType;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is ClassifiedSqlResource && other.resource == resource && other.operation == operation;
  }

  @override
  int get hashCode => Object.hash(resource, operation);
}

class SqlOperationClassification {
  const SqlOperationClassification({
    required this.operation,
    required this.resources,
  });

  final SqlOperation operation;
  final List<ClassifiedSqlResource> resources;
}

abstract final class SqlClassificationReasons {
  static const String emptySql = 'empty_sql';
  static const String multipleStatements = 'multiple_statements';
  static const String unsupportedOperation = 'unsupported_operation';
  static const String noTargetResources = 'no_target_resources';
  static const String nestingLimit = 'nesting_limit';
  static const String unclosedConstruct = 'unclosed_construct';
}

class SqlOperationClassifier {
  static const int maxDerivedTableDepth = 16;

  static final RegExp _identifierStart = RegExp('[a-z_]', caseSensitive: false);
  static final RegExp _identifierPart = RegExp(
    r'[a-z0-9_$#]',
    caseSensitive: false,
  );

  Result<SqlOperationClassification> classify(String sql) {
    return classifyPrepared(PreparedSql.parse(sql));
  }

  Result<SqlOperationClassification> classifyPrepared(PreparedSql prepared) {
    if (prepared.trimmed.isEmpty) {
      return Failure(
        _classificationFailure(
          message: 'SQL cannot be empty',
          reason: SqlClassificationReasons.emptySql,
        ),
      );
    }

    if (prepared.hasMultipleStatements) {
      return Failure(
        _classificationFailure(
          message: 'Multiple SQL statements are not supported',
          reason: SqlClassificationReasons.multipleStatements,
        ),
      );
    }

    final normalized = prepared.stripped.toLowerCase();
    if (normalized.isEmpty) {
      return Failure(
        _classificationFailure(
          message: 'SQL cannot be empty',
          reason: SqlClassificationReasons.emptySql,
        ),
      );
    }

    final operation = _detectOperation(normalized);
    if (operation == null) {
      return Failure(
        _classificationFailure(
          message: 'Unsupported SQL operation',
          reason: SqlClassificationReasons.unsupportedOperation,
        ),
      );
    }

    try {
      final resources = _extractResources(normalized, operation);
      if (resources.isEmpty) {
        return Failure(
          _classificationFailure(
            message: 'Unable to determine SQL target resources',
            reason: SqlClassificationReasons.noTargetResources,
          ),
        );
      }

      return Success(
        SqlOperationClassification(
          operation: operation,
          resources: resources,
        ),
      );
    } on _SqlClassificationAbort catch (error) {
      return Failure(
        _classificationFailure(
          message: error.message,
          reason: error.reason,
        ),
      );
    }
  }

  domain.ValidationFailure _classificationFailure({
    required String message,
    required String reason,
  }) {
    return domain.ValidationFailure.withContext(
      message: message,
      context: {
        'operation': 'sql_classification',
        'reason': reason,
      },
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
    if (sql.startsWith('create ') ||
        sql.startsWith('alter ') ||
        sql.startsWith('drop ') ||
        sql.startsWith('truncate ')) {
      return SqlOperation.ddl;
    }
    return null;
  }

  List<ClassifiedSqlResource> _extractResources(
    String sql,
    SqlOperation operation,
  ) {
    final accesses = <ClassifiedSqlResource>{};
    final cteAliases = _extractCteAliases(sql);

    void addAll(Iterable<DatabaseResource> resources, SqlOperation requiredOperation) {
      for (final resource in resources) {
        if (_isCteAliasReference(resource, cteAliases)) {
          continue;
        }
        accesses.add(
          ClassifiedSqlResource(
            resource: resource,
            operation: requiredOperation,
          ),
        );
      }
    }

    if (operation == SqlOperation.read) {
      addAll(_extractByKeywords(sql, const ['from', 'join', 'apply']), SqlOperation.read);
    } else if (operation == SqlOperation.update) {
      if (sql.startsWith('update ')) {
        final updateTarget = _extractUpdateTarget(sql);
        if (updateTarget != null) {
          addAll(
            [
              DatabaseResource(
                resourceType: DatabaseResourceType.unknown,
                name: updateTarget,
              ),
            ],
            SqlOperation.update,
          );
        }
        addAll(_extractByKeywords(sql, const ['from', 'join', 'apply']), SqlOperation.update);
      } else if (sql.startsWith('insert ')) {
        addAll(_extractByKeywords(sql, const ['into']), SqlOperation.update);
        addAll(_extractByKeywords(sql, const ['from', 'join', 'apply']), SqlOperation.read);
      } else if (sql.startsWith('merge ')) {
        final mergeTarget = _extractMergeTarget(sql);
        if (mergeTarget != null) {
          addAll(
            [
              DatabaseResource(
                resourceType: DatabaseResourceType.unknown,
                name: mergeTarget,
              ),
            ],
            SqlOperation.update,
          );
        }
        addAll(_extractByKeywords(sql, const ['using', 'from', 'join', 'apply']), SqlOperation.read);
      }
    } else if (operation == SqlOperation.delete) {
      addAll(_extractByKeywords(sql, const ['from']), SqlOperation.delete);
      addAll(_extractByKeywords(sql, const ['join', 'apply']), SqlOperation.read);
    } else if (operation == SqlOperation.ddl) {
      final ddlTarget = _extractDdlTarget(sql);
      if (ddlTarget != null) {
        addAll([ddlTarget], SqlOperation.ddl);
        if (ddlTarget.resourceType == DatabaseResourceType.view) {
          addAll(_extractByKeywords(sql, const ['from', 'join', 'apply']), SqlOperation.read);
        }
      }
    }

    return accesses.toList();
  }

  DatabaseResource? _extractDdlTarget(String sql) {
    final lowerSql = sql.toLowerCase();
    String? verb;
    if (lowerSql.startsWith('create ')) {
      verb = 'create';
    } else if (lowerSql.startsWith('alter ')) {
      verb = 'alter';
    } else if (lowerSql.startsWith('drop ')) {
      verb = 'drop';
    } else if (lowerSql.startsWith('truncate ')) {
      verb = 'truncate';
    }
    if (verb == null) {
      return null;
    }

    final objectKeyword = _findDdlObjectKeyword(
      lowerSql,
      _skipWhitespace(sql, verb.length),
      verb: verb,
    );
    if (objectKeyword == null) {
      return null;
    }

    var nextIndex = _skipWhitespace(
      sql,
      objectKeyword.index + objectKeyword.keyword.length,
    );
    nextIndex =
        _skipOptionalKeywordSequence(
          lowerSql,
          sql,
          nextIndex,
          const ['if', 'exists'],
        ) ??
        nextIndex;
    nextIndex =
        _skipOptionalKeywordSequence(
          lowerSql,
          sql,
          nextIndex,
          const ['if', 'not', 'exists'],
        ) ??
        nextIndex;

    final identifier = _readQualifiedIdentifier(sql, nextIndex);
    if (identifier == null || identifier.value.trim().isEmpty) {
      return null;
    }

    return DatabaseResource(
      resourceType: objectKeyword.keyword == 'view' ? DatabaseResourceType.view : DatabaseResourceType.table,
      name: identifier.value,
    );
  }

  _DdlObjectKeyword? _findDdlObjectKeyword(
    String lowerSql,
    int start, {
    required String verb,
  }) {
    final keywords = switch (verb) {
      'truncate' => const ['table'],
      _ => const ['table', 'view'],
    };

    _DdlObjectKeyword? match;
    for (final keyword in keywords) {
      final keywordIndex = _findKeyword(lowerSql, keyword, start);
      if (keywordIndex < 0) {
        continue;
      }
      if (match == null || keywordIndex < match.index) {
        match = _DdlObjectKeyword(keyword: keyword, index: keywordIndex);
      }
    }
    return match;
  }

  int? _skipOptionalKeywordSequence(
    String lowerSql,
    String sql,
    int start,
    List<String> keywords,
  ) {
    var index = _skipWhitespace(sql, start);
    for (final keyword in keywords) {
      if (!_isKeywordAt(lowerSql, keyword, index)) {
        return null;
      }
      index = _skipWhitespace(sql, index + keyword.length);
    }
    return index;
  }

  Set<DatabaseResource> _extractByKeywords(
    String sql,
    List<String> keywords, {
    int subqueryDepth = 0,
  }) {
    final extracted = <DatabaseResource>{};
    final cteAliases = _extractCteAliases(sql);

    for (final keyword in keywords) {
      var searchIndex = 0;
      while (searchIndex < sql.length) {
        final keywordIndex = _findKeyword(sql, keyword, searchIndex);
        if (keywordIndex < 0) {
          break;
        }
        searchIndex = keywordIndex + keyword.length;
        final afterKeyword = _skipWhitespace(sql, searchIndex);
        if (afterKeyword < sql.length && sql[afterKeyword] == '(') {
          if (subqueryDepth >= maxDerivedTableDepth) {
            throw const _SqlClassificationAbort(
              reason: SqlClassificationReasons.nestingLimit,
              message: 'SQL derived-table nesting exceeds the classification limit',
            );
          }
          final close = _findClosingParenthesis(sql, afterKeyword);
          if (close < 0) {
            throw const _SqlClassificationAbort(
              reason: SqlClassificationReasons.unclosedConstruct,
              message: 'Unclosed SQL parenthesis',
            );
          }
          final inner = sql.substring(afterKeyword + 1, close);
          extracted.addAll(
            _extractByKeywords(
              inner,
              const ['from', 'join', 'apply'],
              subqueryDepth: subqueryDepth + 1,
            ),
          );
          searchIndex = close + 1;
          continue;
        }
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

    return extracted.where((resource) => !_isCteAliasReference(resource, cteAliases)).toSet();
  }

  String? _extractUpdateTarget(String sql) {
    final lowerSql = sql.toLowerCase();
    final updateIndex = _findKeyword(lowerSql, 'update', 0);
    if (updateIndex < 0) {
      return null;
    }
    final parsed = _readQualifiedIdentifier(sql, updateIndex + 'update'.length);
    if (parsed == null) {
      return null;
    }

    final hasFromClause =
        _findKeyword(lowerSql, 'from', parsed.nextIndex) >= 0 || _findKeyword(lowerSql, 'join', parsed.nextIndex) >= 0;
    if (hasFromClause && _looksLikeAlias(parsed.value)) {
      return null;
    }
    return parsed.value;
  }

  String? _extractMergeTarget(String sql) {
    final mergeIndex = _findKeyword(sql, 'merge', 0);
    if (mergeIndex < 0) {
      return null;
    }
    var index = _skipWhitespace(sql, mergeIndex + 'merge'.length);
    if (_isKeywordAt(sql, 'into', index)) {
      index = _skipWhitespace(sql, index + 'into'.length);
    }
    final parsed = _readQualifiedIdentifier(sql, index);
    if (parsed == null || parsed.value.trim().isEmpty) {
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
    if (!_isKeywordAt(lowerSql, 'with', index)) {
      return aliases;
    }
    index = _skipWhitespace(sql, index + 4);

    if (_isKeywordAt(lowerSql, 'recursive', index)) {
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
          throw const _SqlClassificationAbort(
            reason: SqlClassificationReasons.unclosedConstruct,
            message: 'Unclosed SQL parenthesis',
          );
        }
        index = _skipWhitespace(sql, closeColumnList + 1);
      }

      if (!_isKeywordAt(lowerSql, 'as', index)) {
        break;
      }
      index = _skipWhitespace(sql, index + 2);
      if (index >= sql.length || sql[index] != '(') {
        break;
      }
      final closeBody = _findClosingParenthesis(sql, index);
      if (closeBody < 0) {
        throw const _SqlClassificationAbort(
          reason: SqlClassificationReasons.unclosedConstruct,
          message: 'Unclosed SQL parenthesis',
        );
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

  int _findKeyword(String sql, String keyword, int start) {
    var index = start;
    while (index < sql.length) {
      final skipped = _skipQuotedRegion(sql, index);
      if (skipped > index) {
        index = skipped;
        continue;
      }
      if (_isKeywordAt(sql, keyword, index)) {
        return index;
      }
      index++;
    }
    return -1;
  }

  bool _isKeywordAt(String lowerSql, String keyword, int index) {
    if (index < 0) {
      return false;
    }
    final end = index + keyword.length;
    if (end > lowerSql.length || !lowerSql.startsWith(keyword, index)) {
      return false;
    }
    return _isWordBoundary(lowerSql, index - 1) && _isWordBoundary(lowerSql, end);
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
        throw const _SqlClassificationAbort(
          reason: SqlClassificationReasons.unclosedConstruct,
          message: 'Unclosed SQL identifier',
        );
      }
      return _ParsedIdentifier(
        value: sql.substring(start, closeIndex + 1),
        nextIndex: closeIndex + 1,
      );
    }
    if (current == '"' || current == '`') {
      final closeIndex = _findClosingDelimiter(sql, start, current);
      if (closeIndex < 0) {
        throw const _SqlClassificationAbort(
          reason: SqlClassificationReasons.unclosedConstruct,
          message: 'Unclosed SQL identifier',
        );
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

  bool _isWordBoundary(String sql, int index) {
    if (index < 0 || index >= sql.length) {
      return true;
    }
    return !_isIdentifierPart(sql[index]);
  }

  int _skipQuotedRegion(String sql, int index) {
    if (index >= sql.length) {
      return index;
    }
    final char = sql[index];
    if (char == "'" || char == '"' || char == '`') {
      final close = _findClosingDelimiter(sql, index, char);
      if (close < 0) {
        throw const _SqlClassificationAbort(
          reason: SqlClassificationReasons.unclosedConstruct,
          message: 'Unclosed SQL literal',
        );
      }
      return close + 1;
    }
    if (char == '[') {
      final close = sql.indexOf(']', index + 1);
      if (close < 0) {
        throw const _SqlClassificationAbort(
          reason: SqlClassificationReasons.unclosedConstruct,
          message: 'Unclosed SQL identifier',
        );
      }
      return close + 1;
    }
    return index;
  }

  int _findClosingDelimiter(String sql, int openIndex, String delimiter) {
    var i = openIndex + 1;
    while (i < sql.length) {
      if (sql[i] == delimiter) {
        if (i + 1 < sql.length && sql[i + 1] == delimiter) {
          i += 2;
          continue;
        }
        return i;
      }
      i++;
    }
    return -1;
  }

  int _findClosingParenthesis(String sql, int openIndex) {
    var depth = 0;
    var i = openIndex;
    while (i < sql.length) {
      final skipped = _skipQuotedRegion(sql, i);
      if (skipped > i) {
        i = skipped;
        continue;
      }
      final char = sql[i];
      if (char == '(') {
        depth++;
      } else if (char == ')') {
        depth--;
        if (depth == 0) {
          return i;
        }
      }
      i++;
    }
    return -1;
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

class _DdlObjectKeyword {
  const _DdlObjectKeyword({
    required this.keyword,
    required this.index,
  });

  final String keyword;
  final int index;
}

class _SqlClassificationAbort implements Exception {
  const _SqlClassificationAbort({
    required this.reason,
    required this.message,
  });

  final String reason;
  final String message;
}
