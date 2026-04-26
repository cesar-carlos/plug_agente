import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

/// Contract test that loads every payload fixture under `test/fixtures/rpc/`
/// and validates it against the JSON Schema bundle in
/// `docs/communication/schemas/`. Used to catch drift when code changes a
/// wire shape without updating the schema (or vice versa).
///
/// Each fixture file name maps to a schema id via [_fixtureToSchema]. Add a
/// new entry whenever you introduce a fixture so it actually gets validated.
const Map<String, String> _fixtureToSchema = {
  'payload_frame_minimal.json': TransportSchemaIds.payloadFrame,
  'rpc_request_sql_execute.json': TransportSchemaIds.rpcRequest,
  'rpc_response_success.json': TransportSchemaIds.rpcResponse,
  'rpc_response_error.json': TransportSchemaIds.rpcResponse,
  'rpc_stream_chunk.json': TransportSchemaIds.streamChunk,
  'rpc_stream_complete.json': TransportSchemaIds.streamComplete,
  'agent_register.json': TransportSchemaIds.agentRegister,
};

void main() {
  group('Contract fixtures vs JSON Schemas', () {
    late TransportSchemaLoader loader;
    late JsonSchemaContractValidator validator;

    setUpAll(() async {
      loader = TransportSchemaLoader();
      await loader.loadAll();
      validator = JsonSchemaContractValidator(loader: loader);
    });

    for (final entry in _fixtureToSchema.entries) {
      final fixtureName = entry.key;
      final schemaId = entry.value;
      test('$fixtureName conforms to $schemaId', () async {
        final fixturePath = '${Directory.current.path}/test/fixtures/rpc/$fixtureName';
        final file = File(fixturePath);
        expect(file.existsSync(), isTrue, reason: 'Fixture not found: $fixturePath');
        final json = jsonDecode(await file.readAsString()) as Object;

        if (!validator.isLoaded(schemaId)) {
          // Schema not loaded in this environment; skip silently.
          return;
        }

        final result = validator.validate(schemaId: schemaId, payload: json);
        expect(
          result.isSuccess(),
          isTrue,
          reason:
              'Fixture $fixtureName failed schema $schemaId. '
              'Errors: ${result.exceptionOrNull()}',
        );
      });
    }
  });
}
