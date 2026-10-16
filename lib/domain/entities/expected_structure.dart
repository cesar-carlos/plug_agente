import 'package:plug_agente/domain/entities/source_schema.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;

class ExpectedStructure {
  const ExpectedStructure(this.resources);
  factory ExpectedStructure.fromJson(Object? value) {
    if (value is! Map || value['version'] != 1 || value.keys.any((k) => !['version', 'resources'].contains(k))) {
      throw domain.ValidationFailure('Invalid structural expectation.');
    }
    final list = value['resources'];
    if (list is! List || list.isEmpty || list.length > 16) throw domain.ValidationFailure('Invalid structure scope.');
    final resources = list.map((raw) {
      if (raw is! Map || raw.keys.any((k) => !['resource', 'columns', 'constraints'].contains(k))) {
        throw domain.ValidationFailure('Invalid resource.');
      }
      final resource = SchemaResource.fromJson(raw['resource']);
      final columns = raw['columns'];
      if (columns is! List || columns.isEmpty || columns.length > 1024) {
        throw domain.ValidationFailure('Invalid columns.');
      }
      final parsed = columns.map((column) {
        if (column is! Map ||
            column.keys.any((k) => !['name', 'nativeType', 'nullable', 'size', 'scale'].contains(k)) ||
            column.length != 5 ||
            column['name'] is! String ||
            !RegExp(r'^[A-Za-z_][A-Za-z0-9_$]*$').hasMatch(column['name'] as String) ||
            (column['name'] as String).length > 128 ||
            column['nativeType'] is! String ||
            (column['nativeType'] as String).isEmpty ||
            (column['nativeType'] as String).length > 128 ||
            column['nullable'] is! bool ||
            [column['size'], column['scale']].any((v) => v != null && (v is! int || v < 0))) {
          throw domain.ValidationFailure('Invalid column expectation.');
        }
        return Map<String, Object?>.from(column);
      }).toList();
      if (parsed.map((c) => c['name']).toSet().length != parsed.length) {
        throw domain.ValidationFailure('Duplicate column.');
      }
      final constraints = raw['constraints'];
      if (constraints != null) {
        if (constraints is! Map ||
            constraints.length != 3 ||
            !['primaryKeys', 'uniqueKeys', 'foreignKeys'].every(constraints.containsKey)) {
          throw domain.ValidationFailure('Invalid constraint expectation.');
        }
        for (final kind in ['primaryKeys', 'uniqueKeys', 'foreignKeys']) {
          final keys = constraints[kind];
          if (keys is! List || keys.length > (kind == 'foreignKeys' ? 128 : 64)) {
            throw domain.ValidationFailure('Invalid keys.');
          }
          final names = <String>{};
          for (final key in keys) {
            if (key is! Map ||
                key['name'] is! String ||
                (key['name'] as String).isEmpty ||
                (key['name'] as String).length > 128 ||
                !names.add(key['name'] as String) ||
                key['status'] != 'enabled' ||
                key.keys.any(
                  (k) => ![
                    'name',
                    'columns',
                    'status',
                    if (kind == 'foreignKeys') ...['target', 'targetColumns'],
                  ].contains(k),
                )) {
              throw domain.ValidationFailure('Only proven enabled keys may be expected.');
            }
            for (final field in ['columns', if (kind == 'foreignKeys') 'targetColumns']) {
              final cols = key[field];
              if (cols is! List ||
                  cols.isEmpty ||
                  cols.length > 32 ||
                  cols.toSet().length != cols.length ||
                  cols.any(
                    (c) => c is! String || !RegExp(r'^[A-Za-z_][A-Za-z0-9_$]*$').hasMatch(c) || c.length > 128,
                  )) {
                throw domain.ValidationFailure('Invalid key columns.');
              }
            }
            if (kind == 'foreignKeys') {
              SchemaResource.fromJson(key['target']);
              if ((key['columns'] as List).length != (key['targetColumns'] as List).length) {
                throw domain.ValidationFailure('Invalid foreign key pairs.');
              }
            }
          }
        }
      }
      return ExpectedResource(
        resource,
        parsed,
        constraints == null ? null : Map<String, Object?>.from(constraints as Map),
      );
    }).toList();
    if (resources.map((r) => '${r.resource.type}:${r.resource.qualified}').toSet().length != resources.length) {
      throw domain.ValidationFailure('Duplicate structure resource.');
    }
    for (final item in resources) {
      for (final key in (item.constraints?['foreignKeys'] as List?) ?? <Object?>[]) {
        final target = SchemaResource.fromJson((key! as Map<Object?, Object?>)['target']);
        if (!resources.any((r) => r.resource.qualified == target.qualified && r.resource.type == target.type)) {
          throw domain.ValidationFailure('Foreign key target must belong to the authorized structure scope.');
        }
      }
    }
    return ExpectedStructure(resources);
  }
  final List<ExpectedResource> resources;

  /// Fixed metadata statements needed on an existing executing connection.
  int get verificationStatementCount => resources.fold(
    0,
    (total, resource) =>
        total +
        2 +
        [
          'primaryKeys',
          'uniqueKeys',
          'foreignKeys',
        ].where((kind) => ((resource.constraints?[kind] as List?) ?? const []).isNotEmpty).length,
  );
  List<String> authorizationSql() => resources
      .map((r) => 'SELECT ${r.columns.map((c) => c['name']).join(',')} FROM ${r.resource.qualified} WHERE 1=0')
      .toList();
}

class ExpectedResource {
  const ExpectedResource(this.resource, this.columns, [this.constraints]);
  final SchemaResource resource;
  final List<Map<String, Object?>> columns;
  final Map<String, Object?>? constraints;
}
