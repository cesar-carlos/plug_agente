import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/utils/rpc_wire_map.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/validation/json_schema_validator.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';
import 'package:plug_agente/infrastructure/validation/schema_loader.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

void main() {
  late _MockFeatureFlags featureFlags;
  late PayloadLogSummarizer summarizer;
  late RpcResponsePreparer preparer;

  setUp(() async {
    featureFlags = _MockFeatureFlags();
    when(() => featureFlags.enableSocketSchemaValidation).thenReturn(true);
    when(() => featureFlags.enableSocketOutgoingContractValidation).thenReturn(true);
    when(() => featureFlags.enableSocketApiVersionMeta).thenReturn(false);
    when(() => featureFlags.enablePayloadSigning).thenReturn(false);
    when(() => featureFlags.requireIncomingPayloadSignatures).thenReturn(false);
    final schemaLoader = TransportSchemaLoader();
    await schemaLoader.loadAll();
    summarizer = PayloadLogSummarizer(thresholdBytes: 8192);
    preparer = RpcResponsePreparer(
      featureFlags: featureFlags,
      logSummarizer: summarizer,
      contractValidator: const RpcContractValidator(),
      protocolProvider: () => const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'gzip',
        negotiatedExtensions: {
          'traceContext': ['w3c-trace-context', 'legacy-trace-id'],
        },
      ),
      usesBinaryTransport: () => true,
      agentIdProvider: () => 'agent-1',
      jsonSchemaValidator: JsonSchemaContractValidator(loader: schemaLoader),
    );
  });

  group('RpcResponsePreparer.prepareForSend', () {
    test('serialises a success response into JSON-RPC envelope', () {
      final response = RpcResponse.success(id: 'req-1', result: {'ok': true});
      final json = preparer.prepareForSend(response);

      expect(json['jsonrpc'], '2.0');
      expect(json['id'], 'req-1');
      expect(json['result'], {'ok': true});
      expect(json.containsKey('error'), isFalse);
    });

    test('serialises an error response with the error envelope', () {
      final response = preparer.buildErrorResponse(
        id: 'req-1',
        code: RpcErrorCode.internalError,
        technicalMessage: 'boom',
      );
      final json = preparer.prepareForSend(response);

      expect(json['error'], isA<Map<String, dynamic>>());
      expect((json['error'] as Map<String, dynamic>)['code'], RpcErrorCode.internalError);
    });

    test('adds api_version + meta when feature flag is on', () {
      when(() => featureFlags.enableSocketApiVersionMeta).thenReturn(true);
      final response = RpcResponse.success(id: 'req-1', result: {'ok': true});
      final json = preparer.prepareForSend(response);

      expect(json['api_version'], isNotNull);
      expect(json['meta'], isA<Map<String, dynamic>>());
      final meta = json['meta'] as Map<String, dynamic>;
      expect(meta['agent_id'], 'agent-1');
      expect(meta['request_id'], 'req-1');
    });

    test('preserves propagated meta.request_id when it differs from response.id', () {
      // Mirrors the future `clientRequestIdEcho` extension where the wire
      // correlator (`meta.request_id`) is the hub UUID set by
      // [attachRequestTrace] while `id` carries the consumer's own id.
      when(() => featureFlags.enableSocketApiVersionMeta).thenReturn(true);
      final response = RpcResponse.success(
        id: 'client-req-42',
        result: {'ok': true},
        meta: const RpcProtocolMeta(requestId: 'hub-uuid-1'),
      );

      final json = preparer.prepareForSend(response);

      final meta = json['meta'] as Map<String, dynamic>;
      expect(json['id'], 'client-req-42');
      expect(meta['request_id'], 'hub-uuid-1');
    });
  });

  group('RpcResponsePreparer.attachRequestTrace', () {
    test('mirrors W3C and legacy trace context from request to response', () {
      const request = RpcRequest(
        jsonrpc: '2.0',
        method: 'sql.execute',
        id: 'req-1',
        meta: RpcProtocolMeta(
          traceId: 'legacy-1',
          traceParent: '00-aaaa-bbbb-01',
          requestId: 'req-1',
        ),
      );
      final response = RpcResponse.success(id: 'req-1', result: 1);

      final traced = preparer.attachRequestTrace(request, response);

      expect(traced.meta?.traceId, 'legacy-1');
      expect(traced.meta?.traceParent, '00-aaaa-bbbb-01');
      expect(traced.meta?.requestId, 'req-1');
    });
  });

  group('RpcResponsePreparer.validateOutgoing', () {
    test('schema refusal preserves consumer and hub correlation with metadata enabled', () {
      when(() => featureFlags.enableSocketApiVersionMeta).thenReturn(true);
      final wire = preparer.prepareForSend(
        RpcResponse.success(
          id: 'consumer-id',
          result: {'invalid': true},
          meta: const RpcProtocolMeta(requestId: 'hub-id'),
        ),
      );
      final result =
          preparer.validateOutgoing(wire, methodsById: {'consumer-id': 'sql.describeSchema'}).getOrThrow()
              as Map<String, dynamic>;
      expect(result['id'], 'consumer-id');
      expect((result['meta'] as Map)['request_id'], 'hub-id');
      expect((result['error'] as Map)['code'], RpcErrorCode.internalError);
      expect(result.containsKey('result'), isFalse);
    });

    test('batch schema refusal preserves each correlation without replaying successes', () {
      when(() => featureFlags.enableSocketApiVersionMeta).thenReturn(true);
      final wires = [
        for (final id in ['one', 'two'])
          preparer.prepareForSend(RpcResponse.success(id: id, result: {'invalid': true})),
      ];
      final result =
          preparer
                  .validateOutgoing(wires, methodsById: {'one': 'sql.describeSchema', 'two': 'sql.describeSchema'})
                  .getOrThrow()
              as List;
      expect(result.map((dynamic v) => (v as Map)['id']), ['one', 'two']);
      for (final dynamic item in result) {
        final value = item as Map;
        expect((value['meta'] as Map)['request_id'], value['id']);
        expect(value.containsKey('result'), isFalse);
      }
    });

    test('returns the original payload when validation passes', () {
      final response = RpcResponse.success(id: 'req-1', result: {'ok': true});
      final wire = preparer.prepareForSend(response);

      final validated = preparer.validateOutgoing(wire);

      expect(validated.getOrThrow(), wire);
    });

    test('skips validation entirely when schema validation flag is off', () {
      when(() => featureFlags.enableSocketSchemaValidation).thenReturn(false);
      final junk = {'not even close to': 'a valid response'};

      final result = preparer.validateOutgoing(junk);

      expect(result.getOrThrow(), junk);
    });

    test('rejects a method-specific success result that violates its schema', () {
      final response = RpcResponse.success(
        id: 'req-1',
        result: const <String, dynamic>{
          'items': <Object>[],
        },
      );
      final wire = preparer.prepareForSend(response);

      final result =
          preparer
                  .validateOutgoing(
                    wire,
                    methodsById: const <Object?, String>{'req-1': 'sql.execute'},
                  )
                  .getOrThrow()
              as Map<String, dynamic>;

      expect(result, isNot(wire));
      final error = result['error'] as Map<String, dynamic>;
      expect(error['code'], RpcErrorCode.internalError);
    });

    test('accepts a method-specific success result that conforms to its schema', () {
      final now = DateTime.utc(2026).toIso8601String();
      final response = RpcResponse.success(
        id: 'req-1',
        result: {
          'execution_id': 'exec-1',
          'started_at': now,
          'finished_at': now,
          'rows': const <Map<String, dynamic>>[],
          'row_count': 0,
        },
      );
      final wire = preparer.prepareForSend(response);

      final result = preparer.validateOutgoing(
        wire,
        methodsById: const <Object?, String>{'req-1': 'sql.execute'},
      );

      expect(result.getOrThrow(), wire);
    });

    test('validateOutgoing sanitizes null optional fields before schema validation', () {
      final now = DateTime.utc(2026).toIso8601String();
      final response = RpcResponse.success(
        id: 'req-1',
        result: {
          'stream_id': 'stream-1',
          'execution_id': 'exec-1',
          'started_at': now,
          'finished_at': now,
          'sql_handling_mode': 'managed',
          'max_rows_handling': 'response_truncation',
          'effective_max_rows': 500,
          'rows': const <Map<String, dynamic>>[],
          'row_count': 0,
          'affected_rows': null,
          'returned_rows': 600,
        },
      );
      final wire = preparer.prepareForSend(response);

      final validated =
          preparer
                  .validateOutgoing(
                    wire,
                    methodsById: const <Object?, String>{'req-1': 'sql.execute'},
                  )
                  .getOrThrow()
              as Map<String, dynamic>;

      final result = validated['result'] as Map<String, dynamic>;
      expect(result.containsKey('affected_rows'), isFalse);
      expect(validated['id'], 'req-1');
    });

    test('sanitizeRpcResponseWirePayload removes null affected_rows from wire', () {
      final wire = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'req-1',
        'result': <String, dynamic>{
          'execution_id': 'exec-1',
          'started_at': DateTime.utc(2026).toIso8601String(),
          'finished_at': DateTime.utc(2026).toIso8601String(),
          'rows': const <Map<String, dynamic>>[],
          'row_count': 0,
          'affected_rows': null,
        },
      };

      final sanitized = RpcWireMap.sanitizeRpcResponseWirePayload(wire) as Map<String, dynamic>;
      final result = sanitized['result'] as Map<String, dynamic>;
      expect(result.containsKey('affected_rows'), isFalse);
    });
  });

  for (final large in [false, true]) {
    test('missing result schema never emits a ${large ? 'large' : 'small'} success payload', () async {
      final loader = TransportSchemaLoader(
        assetLoader: (key) async {
          if (key.endsWith(TransportSchemaIds.resultSourceDiscovery)) throw StateError('missing');
          return File(key).readAsString();
        },
        fileLoader: (_) async => throw StateError('missing'),
      );
      await loader.loadAll();
      final guarded = RpcResponsePreparer(
        featureFlags: featureFlags,
        logSummarizer: summarizer,
        contractValidator: const RpcContractValidator(),
        protocolProvider: () => const ProtocolConfig(protocol: 'jsonrpc-v2', encoding: 'json', compression: 'none'),
        usesBinaryTransport: () => true,
        agentIdProvider: () => 'agent',
        jsonSchemaValidator: JsonSchemaContractValidator(loader: loader),
      );
      final payload = guarded.prepareForSend(
        RpcResponse.success(
          id: 'request',
          result: {
            'data': large ? 'x' * (ConnectionConstants.socketOutgoingContractValidationMaxBytes + 1) : 'data',
          },
        ),
      );
      final result =
          guarded.validateOutgoing(payload, methodsById: {'request': 'sql.describeSource'}).getOrThrow()
              as Map<String, dynamic>;
      expect(result.containsKey('result'), isFalse);
      expect((result['error'] as Map)['code'], RpcErrorCode.internalError);
    });
  }

  group('RpcResponsePreparer.verifyIncomingSignature', () {
    test('returns true when signing is disabled', () {
      expect(preparer.verifyIncomingSignature({'id': 1}), isTrue);
    });

    test('skips logical signature under binary transport when signatureRequired', () {
      final binaryPreparer = RpcResponsePreparer(
        featureFlags: featureFlags,
        logSummarizer: summarizer,
        contractValidator: const RpcContractValidator(),
        protocolProvider: () => const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          signatureRequired: true,
        ),
        usesBinaryTransport: () => true,
        agentIdProvider: () => 'agent-1',
      );

      expect(binaryPreparer.verifyIncomingSignature({'id': 1}), isTrue);
    });

    test('rejects unsigned payload when signatureRequired and non-binary', () {
      final strictPreparer = RpcResponsePreparer(
        featureFlags: featureFlags,
        logSummarizer: summarizer,
        contractValidator: const RpcContractValidator(),
        protocolProvider: () => const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          signatureRequired: true,
        ),
        usesBinaryTransport: () => false,
        agentIdProvider: () => 'agent-1',
      );

      expect(strictPreparer.verifyIncomingSignature({'id': 1}), isFalse);
    });
  });
}
