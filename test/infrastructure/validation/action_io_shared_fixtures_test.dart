import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/action_io_capability.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fixture =
      jsonDecode(File('contracts/action_io_shared_fixtures.json').readAsStringSync()) as Map<String, dynamic>;
  final loader = TransportSchemaLoader();
  const catalog = RpcMethodSchemaCatalog();
  setUpAll(loader.loadAll);
  for (final item in (fixture['cases'] as List).cast<Map<String, dynamic>>()) {
    test('shared I/O contract: ${item['name']}', () {
      if (item['kind'] == 'capability') {
        expect(ActionIoCapability.supported(item['payload']), item['valid']);
        expect(ActionIoCapability.negotiate(ActionIoCapability.advertisement, item['payload']) != null, item['valid']);
        return;
      }
      final method = item['method'] as String;
      final schemaId = switch (item['kind']) {
        'error' => TransportSchemaIds.rpcResponse,
        'params' => catalog.paramsSchemaFor(method),
        _ => catalog.resultSchemaFor(method),
      };
      expect(schemaId, isNotNull);
      final schema = loader.get(schemaId!);
      expect(schema, isNotNull);
      expect(schema!.validate(item['payload']).isValid, item['valid']);
      if (item['kind'] == 'result' && item['valid'] == true) {
        final envelope = loader.get(TransportSchemaIds.rpcResponse)!;
        final checked = envelope.validate({
          'jsonrpc': '2.0',
          'id': 'shared-fixture',
          'result': item['payload'],
        });
        expect(checked.isValid, isTrue, reason: checked.errors.map((error) => error.message).join('; '));
      }
    });
  }
}
