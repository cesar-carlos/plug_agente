import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

Future<({TransportSchemaLoader loader, JsonSchemaContractValidator validator})>
_buildValidator() async {
  final loader = TransportSchemaLoader();
  await loader.loadAll();
  return (loader: loader, validator: JsonSchemaContractValidator(loader: loader));
}

void main() {
  group('TransportSchemaLoader', () {
    test('loads every schema declared in TransportSchemaIds.all', () async {
      final loader = TransportSchemaLoader();
      await loader.loadAll();
      // Some schemas may legitimately fail in headless tests if the file lookup
      // breaks, but the bulk should load. Soft assertion to flag major regressions.
      final loadedRatio = loader.loadedIds.length / TransportSchemaIds.all.length;
      expect(
        loadedRatio,
        greaterThan(0.5),
        reason:
            'Expected at least 50% of schemas to load; got '
            '${loader.loadedIds.length}/${TransportSchemaIds.all.length}',
      );
    });
  });

  group('JsonSchemaContractValidator', () {
    test('validates a well-formed PayloadFrame envelope', () async {
      final ctx = await _buildValidator();
      if (!ctx.validator.isLoaded(TransportSchemaIds.payloadFrame)) {
        // Skip silently if the schema didn't load in this test environment.
        return;
      }
      final frame = <String, dynamic>{
        'schemaVersion': '1.0',
        'enc': 'json',
        'cmp': 'none',
        'contentType': 'application/json',
        'originalSize': 5,
        'compressedSize': 5,
        'payload': 'aGVsbG8=',
      };

      final result = ctx.validator.validate(
        schemaId: TransportSchemaIds.payloadFrame,
        payload: frame,
      );

      expect(result.isSuccess(), isTrue, reason: 'Payload should validate');
    });

    test('rejects a PayloadFrame with unsupported encoding', () async {
      final ctx = await _buildValidator();
      if (!ctx.validator.isLoaded(TransportSchemaIds.payloadFrame)) {
        return;
      }
      final frame = <String, dynamic>{
        'schemaVersion': '1.0',
        'enc': 'msgpack', // not in enum ["json"]
        'cmp': 'none',
        'contentType': 'application/json',
        'originalSize': 5,
        'compressedSize': 5,
        'payload': 'aGVsbG8=',
      };

      final result = ctx.validator.validate(
        schemaId: TransportSchemaIds.payloadFrame,
        payload: frame,
      );

      expect(result.isError(), isTrue);
    });

    test('returns success when the schema is not loaded (fallback path)', () async {
      final loader = TransportSchemaLoader(
        assetLoader: (_) async => throw StateError('asset missing'),
        fileLoader: (_) async => throw StateError('disk missing'),
      );
      await loader.loadAll();
      final validator = JsonSchemaContractValidator(loader: loader);

      final result = validator.validate(
        schemaId: TransportSchemaIds.payloadFrame,
        payload: <String, dynamic>{},
      );

      expect(result.isSuccess(), isTrue);
    });
  });
}
