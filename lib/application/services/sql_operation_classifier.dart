import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/client_permission_set.dart';
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:result_dart/result_dart.dart';

class SqlOperationClassification {
  const SqlOperationClassification({
    required this.operation,
    required this.resources,
  });

  final SqlOperation operation;
  final List<DatabaseResource> resources;
}

class SqlOperationClassifier {
  Result<SqlOperationClassification> classify(String sql) {
    final normalized = _normalizeSql(sql);
    if (normalized.isEmpty) {
      return Failure(domain.ValidationFailure('SQL cannot be empty'));
    }

    if (_containsMultipleStatements(normalized)) {
      return Failure(
        domain.ValidationFailure.withContext(
          message: 'Multiple SQL statements are not supported',
          context: {
            'operation': 'sql_classification',
          },
        ),
      );
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
    if (sql.startsWith('update ') ||
        sql.startsWith('insert ') ||
        sql.startsWith('merge ')) {
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

    switch (operation) {
      case SqlOperation.read:
        resources.addAll(_extractByPatterns(sql, const ['from', 'join']));
      case SqlOperation.update:
        if (sql.startsWith('update ')) {
          resources.addAll(_extractByPatterns(sql, const ['update', 'from']));
        } else if (sql.startsWith('insert ')) {
          resources.addAll(_extractByPatterns(sql, const ['into']));
        } else if (sql.startsWith('merge ')) {
          resources.addAll(_extractByPatterns(sql, const ['merge', 'into']));
        }
      case SqlOperation.delete:
        resources.addAll(_extractByPatterns(sql, const ['from']));
    }

    return resources.toList();
  }

  Set<DatabaseResource> _extractByPatterns(
    String sql,
    List<String> keywords,
  ) {
    final extracted = <DatabaseResource>{};

    for (final keyword in keywords) {
      final pattern = RegExp(
        '$keyword\\s+([\\[\\]\\w\\.]+)',
        caseSensitive: false,
      );
      final matches = pattern.allMatches(sql);
      for (final match in matches) {
        final rawName = match.group(1);
        if (rawName == null || rawName.trim().isEmpty) {
          continue;
        }
        extracted.add(
          DatabaseResource(
            resourceType: DatabaseResourceType.unknown,
            name: rawName,
          ),
        );
      }
    }

    return extracted;
  }

  String _normalizeSql(String sql) {
    final noBlockComments = sql.replaceAll(
      RegExp(r'/\*.*?\*/', dotAll: true),
      ' ',
    );
    final noLineComments = noBlockComments.replaceAll(
      RegExp(r'--.*$', multiLine: true),
      ' ',
    );
    return noLineComments.trim().toLowerCase();
  }

  bool _containsMultipleStatements(String sql) {
    final withoutTrailingSemicolon = sql.trim().replaceFirst(RegExp(r';$'), '');
    return withoutTrailingSemicolon.contains(';');
  }
}
