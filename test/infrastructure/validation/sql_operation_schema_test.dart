import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/external_services/sql_operation_connection_string.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

import '../../application/services/sql_operation_executor_test.dart' show envelope;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('all three RPC methods have real bundled strict request/result schemas', () async {
    final loader = TransportSchemaLoader();
    await loader.loadAll();
    const catalog = RpcMethodSchemaCatalog();
    for (final method in ['sql.operation.execute', 'sql.operation.get', 'sql.operation.cancel']) {
      final params = loader.get(catalog.paramsSchemaFor(method)!);
      final result = loader.get(catalog.resultSchemaFor(method)!);
      expect(params, isNotNull);
      expect(result, isNotNull);
      final raw = envelope();
      if (method != 'sql.operation.execute') {
        raw.remove('steps');
        raw.remove('timeoutMs');
        raw.remove('maxAffectedRows');
      }
      expect(params!.validate(raw).isValid, isTrue);
      expect(params.validate({...raw, 'approved': true}).isValid, isFalse);
      expect(
        result!.validate({
          'operationId': raw['operationId'],
          'fingerprint': raw['fingerprint'],
          'executionId': 'execution',
          'state': 'resultado_desconhecido',
          'directlyAffectedRows': null,
          'updatedAt': '2026-10-10T00:00:00Z',
        }).isValid,
        isTrue,
      );
    }
    final status = loader.get(TransportSchemaIds.resultSqlOperation)!;
    final receipt = {
      'operationId': envelope()['operationId'],
      'fingerprint': 'b' * 64,
      'executionId': 'execution',
      'state': 'cancelada',
      'directlyAffectedRows': null,
      'updatedAt': '2026-10-10T00:00:00Z',
      'failureCode': 'SOURCE_STRUCTURE_MISMATCH',
    };
    expect(status.validate(receipt).isValid, isTrue);
    expect(status.validate({...receipt, 'failureCode': 'PRIVATE_NATIVE_MESSAGE'}).isValid, isFalse);
    expect(status.validate({...receipt, 'state': 'concluida'}).isValid, isFalse);
    final nullScalar = envelope();
    (nullScalar['steps'] as List<Map<String, dynamic>>).first['params'] = {
      'name': {
        'kind': 'value',
        'scalar': {'type': 'null', 'value': null},
      },
    };
    expect(loader.get(TransportSchemaIds.paramsSqlOperationExecute)!.validate(nullScalar).isValid, isTrue);
  });
  test('ODBC database binding cannot modify braced passwords or connection destinations', () {
    final result = SqlOperationConnectionString.bindDatabase(
      'DRIVER={driver};PWD={password;DATABASE=secret};DATABASE=old;DBN=old;',
      'test_db',
    );
    expect(result, 'DRIVER={driver};PWD={password;DATABASE=secret};DATABASE=test_db;DBN=test_db;');
    expect(
      SqlOperationConnectionString.bindDatabase('DBNAME={old};UID=user;', r'C:\fixtures\test.fdb'),
      r'DBNAME=C:\fixtures\test.fdb;UID=user;',
    );
    expect(
      () => SqlOperationConnectionString.bindDatabase('DRIVER={driver};', 'db;SERVER=remote'),
      throwsA(isA<Exception>()),
    );
    expect(() => SqlOperationConnectionString.bindDatabase('PWD={unclosed;', 'test_db'), throwsA(isA<Exception>()));
  });
}
