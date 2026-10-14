import 'package:plug_agente/domain/entities/client_token_policy.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/expected_source.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:result_dart/result_dart.dart';

class SchemaResource {
  const SchemaResource({required this.schema, required this.name, required this.type});
  factory SchemaResource.fromJson(Object? raw) {
    final identifier = RegExp(r'^[A-Za-z_][A-Za-z0-9_$]{0,127}$');
    if (raw is! Map<String, dynamic> ||
        raw.length != 3 ||
        (raw['schema'] != null && (raw['schema'] is! String || !identifier.hasMatch(raw['schema'] as String))) ||
        raw['name'] is! String ||
        !identifier.hasMatch(raw['name'] as String) ||
        !['table', 'view'].contains(raw['type'])) {
      throw ValidationFailure('Invalid schema resource.');
    }
    return SchemaResource(schema: raw['schema'] as String?, name: raw['name'] as String, type: raw['type'] as String);
  }
  final String? schema;
  final String name;
  final String type;
  String get qualified => schema == null ? name : '$schema.$name';
  Map<String, Object?> toJson() => {'schema': schema, 'name': name, 'type': type};
}

class SourceSchemaRequest {
  SourceSchemaRequest.fromJson(Object? raw) {
    if (raw is! Map<String, dynamic> ||
        raw.keys.any(
          (k) => ![
            'contractVersion',
            'database',
            'client_token',
            'expectedSource',
            'resources',
            'offset',
            'pageSize',
          ].contains(k),
        ) ||
        raw['contractVersion'] != 1 ||
        raw['database'] is! String ||
        raw['resources'] is! List) {
      throw ValidationFailure('Invalid source schema request.');
    }
    database = raw['database'] as String;
    if (database.isEmpty || database.length > 500 || RegExp(r'[;{}\r\n\x00]').hasMatch(database)) {
      throw ValidationFailure('Invalid database binding.');
    }
    expected = ExpectedSource.fromJson(raw['expectedSource']);
    resources = (raw['resources'] as List).map(SchemaResource.fromJson).toList();
    offset = raw['offset'] as int? ?? 0;
    pageSize = raw['pageSize'] as int? ?? 4;
    if (resources.isEmpty ||
        resources.length > 16 ||
        offset < 0 ||
        offset >= resources.length ||
        pageSize < 1 ||
        pageSize > 4 ||
        resources.map((r) => '${r.qualified}:${r.type}').toSet().length != resources.length ||
        resources.any((r) => expected.dialect == 'firebird' ? r.schema != null : r.schema == null)) {
      throw ValidationFailure('Specify exact schemas and a bounded unique resource scope.');
    }
  }
  late final String database;
  late final ExpectedSource expected;
  late final List<SchemaResource> resources;
  late final int offset;
  late final int pageSize;
}

abstract interface class ISourceSchemaProbe {
  Future<Result<Map<String, Object?>>> inspect(Config config, SourceSchemaRequest request, ClientTokenPolicy policy);
}
