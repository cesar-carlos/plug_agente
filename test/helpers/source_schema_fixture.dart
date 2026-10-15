import 'package:mocktail/mocktail.dart';
import 'package:odbc_fast/odbc_fast.dart' as odbc;
import 'package:plug_agente/domain/entities/expected_structure.dart';
import 'package:plug_agente/domain/entities/source_schema.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_discovery.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_source_schema.dart';
import 'package:result_dart/result_dart.dart';

class _UnusedSessions extends Mock implements OdbcSourceDiscovery {}

/// Replaces catalog IO only; validation and native result mapping stay real.
class SourceSchemaFixture extends OdbcSourceSchema {
  SourceSchemaFixture(int width) : super(_UnusedSessions()) {
    expected = ExpectedStructure([
      ExpectedResource(
        resource,
        List.generate(
          width,
          (i) => {
            'name': 'column_$i',
            'nativeType': 'int4',
            'nullable': false,
            'size': 10,
            'scale': 0,
          },
        ),
      ),
    ]);
    columnRows = List.generate(width, (i) => ['public', 'fixture', 'column_$i', 'int4', 0, 10, 0]);
  }

  static const resource = SchemaResource(schema: 'public', name: 'fixture', type: 'table');
  late final ExpectedStructure expected;
  late List<List<Object?>> columnRows;
  int catalogCalls = 0;

  @override
  Future<Result<odbc.QueryResult>> catalog(
    String id,
    SchemaResource resource,
    String dialect,
    String kind, {
    Duration Function()? remaining,
  }) async {
    remaining?.call();
    catalogCalls++;
    if (kind == 'tables') {
      return const Success(
        odbc.QueryResult(
          columns: ['TABLE_SCHEM', 'TABLE_NAME', 'TABLE_TYPE'],
          rows: [
            ['public', 'fixture', 'TABLE'],
          ],
          rowCount: 1,
        ),
      );
    }
    if (kind != 'columns') throw StateError('Unexpected catalog kind: $kind');
    return Success(
      odbc.QueryResult(
        columns: ['TABLE_SCHEM', 'TABLE_NAME', 'COLUMN_NAME', 'TYPE_NAME', 'NULLABLE', 'COLUMN_SIZE', 'DECIMAL_DIGITS'],
        rows: columnRows,
        rowCount: columnRows.length,
      ),
    );
  }

  Future<void> validate({String dialect = 'postgres'}) =>
      verifyColumns('fixture', expected, dialect, () => const Duration(seconds: 30));
}
