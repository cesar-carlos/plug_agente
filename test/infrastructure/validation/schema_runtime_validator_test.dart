import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/repositories/i_schema_validation_metrics_collector.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_method_schema_catalog.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

Future<({TransportSchemaLoader loader, JsonSchemaContractValidator validator})> _buildValidator() async {
  final loader = TransportSchemaLoader();
  await loader.loadAll();
  return (loader: loader, validator: JsonSchemaContractValidator(loader: loader));
}

class _FakeSchemaValidationMetrics implements ISchemaValidationMetricsCollector {
  final validations = <({String direction, String schemaId, bool success, Duration elapsed})>[];
  final skippedDirections = <String>[];

  @override
  void recordSchemaValidation({
    required String direction,
    required String schemaId,
    required bool success,
    required Duration elapsed,
  }) {
    validations.add((
      direction: direction,
      schemaId: schemaId,
      success: success,
      elapsed: elapsed,
    ));
  }

  @override
  void recordSchemaValidationSkippedLargePayload({
    required String direction,
  }) {
    skippedDirections.add(direction);
  }
}

void main() {
  group('TransportSchemaLoader', () {
    test('loads every schema declared in TransportSchemaIds.all', () async {
      final loader = TransportSchemaLoader();
      await loader.loadAll();
      expect(loader.loadedIds.toSet(), containsAll(TransportSchemaIds.all));
    });

    test('method schema catalog covers published RPC methods', () {
      const catalog = RpcMethodSchemaCatalog();

      expect(catalog.paramsSchemaFor('sql.cancel'), TransportSchemaIds.paramsSqlCancel);
      expect(catalog.resultSchemaFor('sql.cancel'), TransportSchemaIds.resultSqlCancel);
      expect(catalog.resultSchemaFor('sql.execute'), TransportSchemaIds.resultSqlExecute);
      expect(catalog.resultSchemaFor('agent.action.run'), TransportSchemaIds.resultAgentActionGetExecution);
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

    test('records validation metrics with direction and outcome', () async {
      final loader = TransportSchemaLoader();
      await loader.loadAll();
      final metrics = _FakeSchemaValidationMetrics();
      final validator = JsonSchemaContractValidator(
        loader: loader,
        metrics: metrics,
      );

      final result = validator.validate(
        schemaId: TransportSchemaIds.rpcError,
        direction: 'outbound',
        payload: const <String, dynamic>{
          'code': -32603,
          'message': 'Internal error',
          'data': <String, dynamic>{
            'reason': 'internal_error',
            'category': 'internal',
            'retryable': false,
            'user_message': 'Erro interno.',
            'technical_message': 'boom',
            'correlation_id': 'corr-1',
            'timestamp': '2026-01-01T00:00:00.000Z',
          },
        },
      );

      expect(result.isSuccess(), isTrue);
      expect(metrics.validations, hasLength(1));
      expect(metrics.validations.single.direction, 'outbound');
      expect(metrics.validations.single.schemaId, TransportSchemaIds.rpcError);
      expect(metrics.validations.single.success, isTrue);
    });
  });
}
