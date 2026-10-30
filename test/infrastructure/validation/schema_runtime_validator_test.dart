import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_schema_validation_metrics_collector.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_inbound_schema_validation_pipeline.dart';
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
  test('outgoing envelope accepts scoped lookup miss but rejects arbitrary null execution IDs', () async {
    final built = await _buildValidator();
    const missing = {'found': false, 'execution_id': null, 'reason': 'not_found_in_retention_window'};
    expect(
      built.validator
          .validate(schemaId: TransportSchemaIds.resultAgentActionFindExecution, payload: missing)
          .isSuccess(),
      isTrue,
    );
    for (final (result, accepted) in <(Map<String, Object?>, bool)>[
      (missing, true),
      ({'execution_id': 'legacy-execution'}, true),
      ({'execution_id': null}, false),
      ({'found': true, 'execution_id': null, 'reason': 'not_found_in_retention_window'}, false),
      ({'found': false, 'execution_id': null, 'reason': 'other'}, false),
    ]) {
      expect(
        built.validator
            .validate(
              schemaId: TransportSchemaIds.rpcResponse,
              payload: {
                'jsonrpc': '2.0',
                'id': 'lookup',
                'result': result,
              },
            )
            .isSuccess(),
        accepted,
        reason: '$result',
      );
    }
  });
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
      expect(ctx.validator.isLoaded(TransportSchemaIds.payloadFrame), isTrue);
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
      expect(ctx.validator.isLoaded(TransportSchemaIds.payloadFrame), isTrue);
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

    test('accepts sql.execute offset pagination options', () async {
      final ctx = await _buildValidator();
      expect(ctx.validator.isLoaded(TransportSchemaIds.paramsSqlExecute), isTrue);

      final result = ctx.validator.validate(
        schemaId: TransportSchemaIds.paramsSqlExecute,
        payload: const <String, dynamic>{
          'sql': 'SELECT CodCliente, Nome FROM Cliente ORDER BY CodCliente',
          'options': <String, dynamic>{
            'page': 1,
            'page_size': 10,
          },
        },
      );

      expect(result.isSuccess(), isTrue);
    });

    test('rejects sql.execute preserve mode combined with pagination options', () async {
      final ctx = await _buildValidator();
      expect(ctx.validator.isLoaded(TransportSchemaIds.paramsSqlExecute), isTrue);

      final result = ctx.validator.validate(
        schemaId: TransportSchemaIds.paramsSqlExecute,
        payload: const <String, dynamic>{
          'sql': 'SELECT CodCliente, Nome FROM Cliente ORDER BY CodCliente',
          'options': <String, dynamic>{
            'page': 1,
            'page_size': 10,
            'execution_mode': 'preserve',
          },
        },
      );

      expect(result.isError(), isTrue);
    });

    test('fails closed when the schema is not loaded', () async {
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

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as domain.ConfigurationFailure;
      expect(failure.code, 'SCHEMA_UNAVAILABLE');
      expect(failure.context['schema_id'], TransportSchemaIds.payloadFrame);
    });

    for (final brokenContent in <String?>[null, '{invalid json', '{"type": "not-a-json-type"}']) {
      test('refuses a missing or invalid required schema: $brokenContent', () async {
        final loader = TransportSchemaLoader(
          assetLoader: (key) async {
            if (key.endsWith(TransportSchemaIds.paramsSourceSchema)) {
              if (brokenContent == null) throw StateError('missing asset');
              return brokenContent;
            }
            return File(key).readAsString();
          },
          fileLoader: (_) async => throw StateError('missing disk fallback'),
        );
        await loader.loadAll();
        final metrics = _FakeSchemaValidationMetrics();
        final validator = JsonSchemaContractValidator(loader: loader, metrics: metrics);
        final pipeline = RpcInboundSchemaValidationPipeline(
          jsonSchemaValidator: validator,
          logSummarizer: PayloadLogSummarizer(thresholdBytes: 8192),
        );
        final request = <String, dynamic>{
          'jsonrpc': '2.0',
          'id': 'request',
          'method': 'sql.describeSchema',
          'params': <String, dynamic>{},
        };
        expect(pipeline.validateRequestEnvelope(request), isNull);
        final failure = pipeline.validateRequestParams(request);
        expect(failure, isA<domain.ConfigurationFailure>());
        expect(failure!.code, 'SCHEMA_UNAVAILABLE');
        expect(metrics.validations.last.success, isFalse);
        expect(pipeline.validateCriticalFieldsWhenSkipping(request), isA<domain.ConfigurationFailure>());
      });
    }

    test('missing referenced error schema prevents response validation', () async {
      final loader = TransportSchemaLoader(
        assetLoader: (key) async {
          if (key.endsWith(TransportSchemaIds.rpcError)) throw StateError('missing');
          return File(key).readAsString();
        },
        fileLoader: (_) async => throw StateError('missing'),
      );
      await loader.loadAll();
      final validator = JsonSchemaContractValidator(loader: loader);
      expect(
        validator
            .validate(
              schemaId: TransportSchemaIds.rpcResponse,
              payload: {
                'jsonrpc': '2.0',
                'id': 'request',
                'error': {'code': -32000, 'message': 'refused'},
              },
            )
            .isError(),
        isTrue,
      );
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
