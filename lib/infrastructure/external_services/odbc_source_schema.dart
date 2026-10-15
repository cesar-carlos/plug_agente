import 'dart:convert';

import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/expected_structure.dart';
import 'package:plug_agente/domain/entities/source_schema.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/value_objects/database_resource.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:plug_agente/infrastructure/external_services/source_schema_sql.dart';
import 'package:result_dart/result_dart.dart';

/// Fixed dialect catalogs over ODBC. No caller SQL, defaults, remarks or business rows.
class OdbcSourceSchema implements ISourceSchemaProbe {
  const OdbcSourceSchema(this.sessions);
  final OdbcSourceDiscovery sessions;
  static bool allowed(ClientTokenPolicy policy, SchemaResource resource) {
    if (policy.isRevoked) return false;
    if (policy.usesGlobalScope) {
      return (resource.type == 'table' ? policy.allTables : policy.allViews) && policy.globalPermissions.canRead;
    }
    final rules = policy.rules.where(
      (r) =>
          r.resource.normalizedName == resource.qualified.toLowerCase() &&
          (r.resource.resourceType == DatabaseResourceType.unknown || r.resource.resourceType.name == resource.type),
    );
    return !rules.any((r) => r.effect == ClientTokenRuleEffect.deny && r.permissions.canRead) &&
        rules.any((r) => r.effect == ClientTokenRuleEffect.allow && r.permissions.canRead);
  }

  @override
  Future<Result<Map<String, Object?>>> inspect(Config config, SourceSchemaRequest request, ClientTokenPolicy policy) =>
      sessions.withConnection(
        config,
        request.database,
        (id, remaining) async {
          final proof = await OdbcSourceDiscovery.inspectConnection(sessions.service, id, config, request.database);
          request.expected.verify(proof);
          final results = <Map<String, Object?>>[];
          for (final resource in request.resources.skip(request.offset).take(request.pageSize)) {
            remaining();
            results.add(
              allowed(policy, resource)
                  ? await readResource(id, resource, request, policy, remaining)
                  : empty(resource, 'not_authorized'),
            );
            remaining();
          }
          request.expected.verify(
            await OdbcSourceDiscovery.inspectConnection(sessions.service, id, config, request.database),
          );
          remaining();
          final result = <String, Object?>{
            'contractVersion': 1,
            'identity': proof.toJson(),
            'observedAt': DateTime.now().toUtc().toIso8601String(),
            'resources': results,
            'metadataPage': {
              'offset': request.offset,
              'pageSize': request.pageSize,
              'nextOffset': request.offset + results.length < request.resources.length
                  ? request.offset + results.length
                  : null,
            },
          };
          if (utf8.encode(jsonEncode(result)).length > 1024 * 1024) {
            throw domain.ValidationFailure('Schema response budget exceeded.');
          }
          return result;
        },
        timeout: const Duration(seconds: 30),
        maxResultBufferBytes: 1024 * 1024,
      );

  /// Only used by the already authorized verified SELECT, on its existing connection.
  Future<void> verifyColumns(
    String id,
    ExpectedStructure expected,
    String dialect,
    Duration Function() remaining,
  ) async {
    for (final item in expected.resources) {
      final tables = await rows(catalog(id, item.resource, dialect, 'tables', remaining: remaining));
      final present = tables
          .where((r) => matches(r, item.resource, dialect) && text(r['TABLE_TYPE']).toLowerCase() == item.resource.type)
          .toList();
      if (present.length != 1) {
        throw domain.DatabaseFailure.withContext(
          code: 'SOURCE_STRUCTURE_MISMATCH',
          message: 'Used source structure differs from the published expectation.',
          context: const {'retryable': false},
        );
      }
      final columns = await rows(catalog(id, item.resource, dialect, 'columns', remaining: remaining));
      final columnsByName = <String, Map<String, Object?>?>{};
      for (final column in columns) {
        if (!matches(column, item.resource, dialect)) continue;
        final name = text(column['COLUMN_NAME']);
        final canonicalName = dialect == 'firebird' ? name.toUpperCase() : name;
        // A duplicate remains ambiguous even when both definitions are equal.
        columnsByName.update(canonicalName, (_) => null, ifAbsent: () => column);
      }
      for (final expectedColumn in item.columns) {
        final name = expectedColumn['name']! as String;
        final column = columnsByName[dialect == 'firebird' ? name.toUpperCase() : name];
        if (column == null) {
          throw domain.DatabaseFailure.withContext(
            code: 'SOURCE_STRUCTURE_MISMATCH',
            message: 'Used source structure differs from the published expectation.',
            context: const {'retryable': false},
          );
        }
        final nullable = integer(column['NULLABLE']);
        if (text(column['TYPE_NAME']).toLowerCase() != (expectedColumn['nativeType']! as String).toLowerCase() ||
            nullable == null ||
            nullable > 1 ||
            nullable < 0 ||
            (nullable == 1) != expectedColumn['nullable'] ||
            integer(column['COLUMN_SIZE']) != expectedColumn['size'] ||
            integer(column['DECIMAL_DIGITS']) != expectedColumn['scale']) {
          throw domain.DatabaseFailure.withContext(
            code: 'SOURCE_STRUCTURE_MISMATCH',
            message: 'Used source structure differs from the published expectation.',
            context: const {'retryable': false},
          );
        }
      }
      final constraints = item.constraints;
      if (constraints != null) {
        for (final kind in ['primaryKeys', 'uniqueKeys', 'foreignKeys']) {
          final wanted = constraints[kind]! as List;
          if (wanted.isEmpty) continue;
          final raw = await rows(
            catalog(
              id,
              item.resource,
              dialect,
              kind == 'primaryKeys'
                  ? 'primary'
                  : kind == 'uniqueKeys'
                  ? 'unique'
                  : 'foreign',
              remaining: remaining,
            ),
          );
          final actual = kind == 'foreignKeys'
              ? foreignConstraints(raw)
              : keys(raw, 'PK_NAME', 'COLUMN_NAME', 'KEY_SEQ');
          for (final key in wanted) {
            if (!actual.any((candidate) => sameKey(candidate, key as Map<Object?, Object?>, dialect))) {
              throw domain.DatabaseFailure.withContext(
                code: 'SOURCE_STRUCTURE_MISMATCH',
                message: 'Used source constraint differs from the published expectation.',
                context: const {'retryable': false},
              );
            }
          }
        }
      }
    }
  }

  Future<Result<odbc.QueryResult>> catalog(
    String id,
    SchemaResource resource,
    String dialect,
    String kind, {
    Duration Function()? remaining,
  }) {
    remaining?.call();
    return sessions.service.executeQueryNamed(id, SourceSchemaSql.query(dialect, kind), {
      if (dialect != 'firebird') 'schema': resource.schema,
      'table': dialect == 'firebird' ? resource.name.toUpperCase() : resource.name,
    });
  }

  static Map<String, Object?> empty(SchemaResource resource, String status) => {
    'resource': resource.toJson(),
    'status': status,
    'columns': <Object?>[],
    'primaryKeys': <Object?>[],
    'uniqueKeys': <Object?>[],
    'foreignKeys': <Object?>[],
    'coverage': {
      'columns': false,
      'primaryKeys': false,
      'foreignKeys': false,
      'constraintStatus': false,
      'uniqueKeys': false,
    },
    'limitations': status == 'unavailable' ? ['metadata_unavailable'] : <String>[],
  };

  Future<List<Map<String, Object?>>> rows(Future<Result<odbc.QueryResult>> call) async {
    final result = (await call).getOrThrow();
    if (result.rows.length != result.rowCount ||
        result.rowCount > 4096 ||
        result.additionalResults.isNotEmpty ||
        result.refCursorResults.isNotEmpty) {
      throw domain.ValidationFailure('Incomplete catalog metadata.');
    }
    return result.rows.map((row) {
      if (row.length != result.columns.length) throw domain.ValidationFailure('Invalid catalog metadata.');
      return <String, Object?>{for (var i = 0; i < row.length; i++) result.columns[i].toUpperCase(): row[i]};
    }).toList();
  }

  static String text(Object? value) => value is String ? value.trim() : '';
  static int? integer(Object? value) => value is int
      ? value
      : value is num && value.isFinite && value == value.roundToDouble()
      ? value.toInt()
      : int.tryParse(text(value));
  static bool matches(Map<String, Object?> row, SchemaResource resource, String dialect, {String prefix = 'TABLE_'}) {
    String canonical(String s) => dialect == 'firebird' ? s.toUpperCase() : s;
    return canonical(text(row['${prefix}NAME'])) == canonical(resource.name) &&
        (resource.schema == null
            ? text(row['${prefix}SCHEM']).isEmpty
            : text(row['${prefix}SCHEM']) == resource.schema);
  }

  Future<Map<String, Object?>> readResource(
    String id,
    SchemaResource resource,
    SourceSchemaRequest request,
    ClientTokenPolicy policy,
    Duration Function() remaining,
  ) async {
    try {
      final tables = await rows(catalog(id, resource, request.expected.dialect, 'tables', remaining: remaining));
      final present = tables
          .where(
            (r) =>
                matches(r, resource, request.expected.dialect) && text(r['TABLE_TYPE']).toLowerCase() == resource.type,
          )
          .toList();
      // Empty driver catalogs cannot prove absence under limited metadata visibility.
      if (present.length != 1) return empty(resource, 'unavailable');
      final columns = (await rows(
        catalog(id, resource, request.expected.dialect, 'columns', remaining: remaining),
      )).where((r) => matches(r, resource, request.expected.dialect)).toList();
      if (columns.isEmpty || columns.length > 1024) return empty(resource, 'unavailable');
      final result = empty(resource, 'available');
      result['columns'] = columns
          .map(
            (r) => {
              'name': text(r['COLUMN_NAME']),
              'nativeType': text(r['TYPE_NAME']),
              'ordinal': integer(r['ORDINAL_POSITION']),
              'nullable': integer(r['NULLABLE']) == 0
                  ? false
                  : integer(r['NULLABLE']) == 1
                  ? true
                  : null,
              'size': integer(r['COLUMN_SIZE']),
              'scale': integer(r['DECIMAL_DIGITS']),
            },
          )
          .toList();
      final coverage = result['coverage']! as Map<String, bool>;
      coverage['columns'] = true;
      result['limitations'] = ['constraint_status_unverified', 'scoped_relationships'];
      try {
        final primary = (await rows(
          catalog(id, resource, request.expected.dialect, 'primary', remaining: remaining),
        )).where((r) => matches(r, resource, request.expected.dialect)).toList();
        result['primaryKeys'] = keys(primary, 'PK_NAME', 'COLUMN_NAME', 'KEY_SEQ');
        coverage['primaryKeys'] = true;
      } on Object {
        result['limitations'] = ['metadata_unavailable', 'constraint_status_unverified', 'scoped_relationships'];
      }
      try {
        final foreign = (await rows(
          catalog(id, resource, request.expected.dialect, 'foreign', remaining: remaining),
        )).where((r) => matches(r, resource, request.expected.dialect, prefix: 'FKTABLE_')).toList();
        final grouped = <String, List<Map<String, Object?>>>{};
        for (final row in foreign) {
          final targets = request.resources
              .where((t) => matches(row, t, request.expected.dialect, prefix: 'PKTABLE_') && allowed(policy, t))
              .toList();
          if (targets.length != 1) continue;
          final name = text(row['FK_NAME']);
          if (name.isEmpty) throw domain.ValidationFailure('Foreign key name unavailable.');
          grouped.putIfAbsent(name, () => []).add({...row, 'target': targets.single.toJson()});
        }
        result['foreignKeys'] = grouped.entries.map((entry) {
          final sorted = ordered(entry.value, 'KEY_SEQ');
          return {
            'name': entry.key,
            'columns': sorted.map((r) => text(r['FKCOLUMN_NAME'])).toList(),
            'target': sorted.first['target'],
            'targetColumns': sorted.map((r) => text(r['PKCOLUMN_NAME'])).toList(),
            'status': keyStatus(sorted),
          };
        }).toList();
        coverage['foreignKeys'] = true;
      } on Object {
        result['limitations'] = ['metadata_unavailable', 'constraint_status_unverified', 'scoped_relationships'];
      }
      try {
        final unique = (await rows(
          catalog(id, resource, request.expected.dialect, 'unique', remaining: remaining),
        )).where((r) => matches(r, resource, request.expected.dialect)).toList();
        result['uniqueKeys'] = keys(unique, 'PK_NAME', 'COLUMN_NAME', 'KEY_SEQ');
        coverage['uniqueKeys'] = true;
      } on Object {
        result['limitations'] = ['metadata_unavailable', 'constraint_status_unverified', 'scoped_relationships'];
      }
      coverage['constraintStatus'] =
          coverage['primaryKeys']! &&
          coverage['foreignKeys']! &&
          coverage['uniqueKeys']! &&
          [
            'primaryKeys',
            'uniqueKeys',
            'foreignKeys',
          ].every(
            (kind) => (result[kind]! as List).every((k) => (k as Map<Object?, Object?>)['status'] != 'unknown'),
          ) &&
          request.expected.dialect != 'sybase';
      if (coverage['constraintStatus']!) result['limitations'] = ['scoped_relationships'];
      return result;
    } on Object {
      return empty(resource, 'unavailable');
    }
  }

  static bool sameKey(Map<String, Object?> a, Map<Object?, Object?> b, String dialect) =>
      a['name'] == b['name'] &&
      a['status'] == b['status'] &&
      _sameColumnNames(a['columns'], b['columns']) &&
      _sameColumnNames(a['targetColumns'], b['targetColumns']) &&
      (a['target'] == null && b['target'] == null ||
          a['target'] is Map &&
              b['target'] is Map &&
              [
                'schema',
                'name',
                'type',
              ].every(
                (k) => (dialect == 'firebird' && k == 'name'
                    ? text((a['target']! as Map<Object?, Object?>)[k]).toUpperCase() ==
                          text((b['target']! as Map<Object?, Object?>)[k]).toUpperCase()
                    : (a['target']! as Map<Object?, Object?>)[k] == (b['target']! as Map<Object?, Object?>)[k]),
              ));

  static bool _sameColumnNames(Object? a, Object? b) {
    if (a == null && b == null) return true;
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        final left = a[i];
        final right = b[i];
        if (left is! String || right is! String) {
          return jsonEncode(a) == jsonEncode(b);
        }
        if (left != right) return false;
      }
      return true;
    }
    return jsonEncode(a) == jsonEncode(b);
  }

  static List<Map<String, Object?>> foreignConstraints(List<Map<String, Object?>> raw) {
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in raw) {
      grouped.putIfAbsent(text(row['FK_NAME']), () => []).add(row);
    }
    return grouped.entries.map((entry) {
      final sorted = ordered(entry.value, 'KEY_SEQ');
      final first = sorted.first;
      return <String, Object?>{
        'name': entry.key,
        'columns': sorted.map((r) => text(r['FKCOLUMN_NAME'])).toList(),
        'target': {
          'schema': text(first['PKTABLE_SCHEM']).isEmpty ? null : text(first['PKTABLE_SCHEM']),
          'name': text(first['PKTABLE_NAME']),
          'type': 'table',
        },
        'targetColumns': sorted.map((r) => text(r['PKCOLUMN_NAME'])).toList(),
        'status': keyStatus(sorted),
      };
    }).toList();
  }

  static String keyStatus(List<Map<String, Object?>> rows) {
    final states = rows.map((r) => text(r['CONSTRAINT_STATUS'])).toSet();
    return states.length == 1 && ['enabled', 'disabled', 'unvalidated'].contains(states.single)
        ? states.single
        : 'unknown';
  }

  static List<Map<String, Object?>> ordered(List<Map<String, Object?>> rows, String sequence) {
    final sorted = [...rows]..sort((a, b) => (integer(a[sequence]) ?? 0).compareTo(integer(b[sequence]) ?? 0));
    for (var i = 0; i < sorted.length; i++) {
      if (integer(sorted[i][sequence]) != i + 1) throw domain.ValidationFailure('Incomplete composite key metadata.');
    }
    return sorted;
  }

  static List<Map<String, Object?>> keys(List<Map<String, Object?>> rows, String key, String column, String sequence) {
    final grouped = <String, List<Map<String, Object?>>>{};
    for (final row in rows) {
      final name = text(row[key]);
      if (name.isEmpty) throw domain.ValidationFailure('Key name unavailable.');
      grouped.putIfAbsent(name, () => []).add(row);
    }
    return grouped.entries
        .map(
          (entry) => <String, Object?>{
            'name': entry.key,
            'columns': ordered(entry.value, sequence).map((r) => text(r[column])).toList(),
            'status': keyStatus(entry.value),
          },
        )
        .toList();
  }
}
