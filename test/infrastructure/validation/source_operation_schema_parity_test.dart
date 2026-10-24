import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/rpc/sql_operation_params_reader.dart';
import 'package:plug_agente/domain/entities/source_schema.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/errors/sql_operation_failure.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

import '../../application/services/sql_operation_executor_test.dart' show envelope;

Map<String, dynamic> _schemaRequest() => {
  'contractVersion': 1,
  'database': 'test_db',
  'expectedSource': {'version': 1, 'dialect': 'postgres', 'identityHash': 'a' * 64},
  'resources': [
    <String, dynamic>{'schema': 'public', 'name': 'example', 'type': 'table'},
  ],
  'offset': 0,
  'pageSize': 4,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TransportSchemaLoader loader;
  setUpAll(() async {
    loader = TransportSchemaLoader();
    await loader.loadAll();
  });

  test('schema and reader accept an explicit bounded metadata page', () {
    final request = _schemaRequest();
    expect(loader.get(TransportSchemaIds.paramsSourceSchema)!.validate(request).isValid, isTrue);
    final parsed = SourceSchemaRequest.fromJson(request);
    expect(parsed.offset, 0);
    expect(parsed.pageSize, 4);
  });

  final invalid = <String, void Function(Map<String, dynamic>)>{
    'missing offset': (p) => p.remove('offset'),
    'missing pageSize': (p) => p.remove('pageSize'),
    'null offset': (p) => p['offset'] = null,
    'string pageSize': (p) => p['pageSize'] = '4',
    'too large page': (p) => p['pageSize'] = 5,
    'unsafe database': (p) => p['database'] = 'test;SERVER=other',
    'duplicate resource': (p) => (p['resources'] as List).add((p['resources'] as List).first),
    'null schema': (p) => ((p['resources'] as List).first as Map)['schema'] = null,
    'unsupported dialect': (p) => (p['expectedSource'] as Map)['dialect'] = 'firebird',
  };
  for (final entry in invalid.entries) {
    test('schema and reader reject ${entry.key}', () {
      final request = _schemaRequest();
      entry.value(request);
      expect(loader.get(TransportSchemaIds.paramsSourceSchema)!.validate(request).isValid, isFalse);
      expect(() => SourceSchemaRequest.fromJson(request), throwsA(isA<ValidationFailure>()));
    });
  }

  test('reader additionally checks the offset against the supplied scope', () {
    final request = _schemaRequest()..['offset'] = 1;
    expect(loader.get(TransportSchemaIds.paramsSourceSchema)!.validate(request).isValid, isTrue);
    expect(() => SourceSchemaRequest.fromJson(request), throwsA(isA<ValidationFailure>()));
  });

  for (final dialect in ['postgres', 'mssql', 'sybase', 'firebird']) {
    test('all expected-source contracts agree on dialect $dialect', () {
      final expected = {'version': 1, 'dialect': dialect, 'identityHash': 'a' * 64};
      final plan = envelope()..['expectedSource'] = expected;
      final reference = Map<String, dynamic>.from(plan)
        ..remove('steps')
        ..remove('timeoutMs')
        ..remove('maxAffectedRows');
      final requests = {
        TransportSchemaIds.paramsSourceSchema: _schemaRequest()..['expectedSource'] = expected,
        TransportSchemaIds.paramsSqlExecute: {
          'sql': 'SELECT id FROM example',
          'database': 'test_db',
          'expectedSource': expected,
        },
        TransportSchemaIds.paramsSqlOperationExecute: plan,
        TransportSchemaIds.paramsSqlOperationReference: reference,
      };
      for (final entry in requests.entries) {
        expect(loader.get(entry.key)!.validate(entry.value).isValid, dialect != 'firebird', reason: entry.key);
      }
      if (dialect == 'firebird') {
        expect(() => const SqlOperationParamsReader().plan(plan), throwsA(isA<ValidationFailure>()));
      } else {
        expect(const SqlOperationParamsReader().plan(plan).expectedSource!.dialect, dialect);
      }
      final identity = {
        'contractVersion': 1,
        'database': 'test_db',
        'dialect': dialect,
        'identityHash': 'a' * 64,
        'identityKind': dialect == 'sybase' ? 'provisioned' : 'native',
        'engineVersion': 'fixture',
        'verifiedAt': '2026-10-24T00:00:00Z',
      };
      expect(loader.get(TransportSchemaIds.resultSourceDiscovery)!.validate(identity).isValid, dialect != 'firebird');
      expect(
        loader.get(TransportSchemaIds.resultSourceSchema)!.validate({
          'contractVersion': 1,
          'identity': identity,
          'observedAt': identity['verifiedAt'],
          'resources': <Object?>[],
          'metadataPage': {'offset': 0, 'pageSize': 4, 'nextOffset': null},
        }).isValid,
        dialect != 'firebird',
      );
    });
  }

  const sqlByteLimit = 1048576;
  const planByteLimit = 2097152;
  const reader = SqlOperationParamsReader();
  test('SQL UTF-8 limit accepts exact bytes and rejects one additional multibyte character', () {
    final plan = envelope();
    final step = (plan['steps'] as List).first as Map;
    step['sql'] = 'é' * (sqlByteLimit ~/ 2);
    expect(loader.get(TransportSchemaIds.paramsSqlOperationExecute)!.validate(plan).isValid, isTrue);
    expect(reader.plan(plan).steps.first.sql.length, sqlByteLimit ~/ 2);
    step['sql'] = '${step['sql']}é';
    expect(loader.get(TransportSchemaIds.paramsSqlOperationExecute)!.validate(plan).isValid, isTrue);
    expect(() => reader.plan(plan), throwsA(isA<SqlOperationFailure>()));
  });

  test('serialized plan byte limit is enforced independently of each SQL length', () {
    final plan = envelope();
    final steps = plan['steps'] as List;
    (steps.first as Map)['sql'] = 'a' * sqlByteLimit;
    (steps.last as Map)['sql'] = 'a';
    final remaining = planByteLimit - utf8.encode(jsonEncode(plan)).length;
    (steps.last as Map)['sql'] = 'a' * (remaining + 1);
    expect(utf8.encode(jsonEncode(plan)).length, planByteLimit);
    expect(loader.get(TransportSchemaIds.paramsSqlOperationExecute)!.validate(plan).isValid, isTrue);
    expect(reader.plan(plan).steps, hasLength(2));
    (steps.last as Map)['sql'] = '${(steps.last as Map)['sql']}a';
    expect(() => reader.plan(plan), throwsA(isA<SqlOperationFailure>()));
  });
}
