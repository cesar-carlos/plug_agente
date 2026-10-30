import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('I/O methods load strict dedicated parameter and result schemas', () async {
    final loader = TransportSchemaLoader();
    await loader.loadAll();
    const catalog = RpcMethodSchemaCatalog();
    for (final method in ['sendInput', 'closeInput', 'getInputStatus', 'readIo', 'findExecution']) {
      final params = loader.get(catalog.paramsSchemaFor('agent.action.$method')!);
      final result = loader.get(catalog.resultSchemaFor('agent.action.$method')!);
      expect(params, isNotNull);
      expect(result, isNotNull);
      expect(params!.validate({'approved': true}).isValid, isFalse);
      expect(result!.validate({'approved': true}).isValid, isFalse);
    }
    final read = loader.get(TransportSchemaIds.paramsAgentActionReadIo)!;
    final request = {'execution_id': 'execution', 'after_sequence': 0, 'max_bytes': 65536, 'wait_ms': 20000};
    expect(read.validate(request).isValid, isTrue);
    expect(read.validate({...request, 'max_bytes': 1}).isValid, isFalse);
    expect(read.validate({...request, 'wait_ms': 20001}).isValid, isFalse);
    final input = loader.get(TransportSchemaIds.paramsAgentActionSendInput)!;
    final message = {'execution_id': 'execution', 'message_id': 'message', 'sequence': 0, 'data_base64': ''};
    expect(input.validate(message).isValid, isTrue);
    expect(input.validate({...message, 'data_base64': '_w=='}).isValid, isFalse);
    final status = loader.get(TransportSchemaIds.resultAgentActionGetInputStatus)!;
    final receipt = {
      'execution_id': 'execution',
      'message_id': 'message',
      'sequence': 0,
      'state': 'unknown',
      'confirmed_bytes': null,
      'next_input_sequence': 1,
      'stdin_state': 'failed',
    };
    expect(status.validate(receipt).isValid, isTrue);
    expect(status.validate({...receipt, 'state': 'consumed'}).isValid, isFalse);
    expect(status.validate({...receipt, 'confirmed_bytes': -1}).isValid, isFalse);
  });
}
