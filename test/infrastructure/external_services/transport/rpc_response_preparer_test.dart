import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_log_summarizer.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_response_preparer.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

void main() {
  late _MockFeatureFlags featureFlags;
  late PayloadLogSummarizer summarizer;
  late RpcResponsePreparer preparer;

  setUp(() {
    featureFlags = _MockFeatureFlags();
    when(() => featureFlags.enableSocketSchemaValidation).thenReturn(true);
    when(() => featureFlags.enableSocketOutgoingContractValidation).thenReturn(true);
    when(() => featureFlags.enableSocketApiVersionMeta).thenReturn(false);
    when(() => featureFlags.enablePayloadSigning).thenReturn(false);
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
    test('returns the original payload when validation passes', () {
      final response = RpcResponse.success(id: 'req-1', result: {'ok': true});
      final wire = preparer.prepareForSend(response);

      final validated = preparer.validateOutgoing(wire);

      expect(validated, wire);
    });

    test('skips validation entirely when schema validation flag is off', () {
      when(() => featureFlags.enableSocketSchemaValidation).thenReturn(false);
      final junk = {'not even close to': 'a valid response'};

      final result = preparer.validateOutgoing(junk);

      expect(result, junk);
    });
  });

  group('RpcResponsePreparer.verifyIncomingSignature', () {
    test('returns true when signing is disabled', () {
      expect(preparer.verifyIncomingSignature({'id': 1}), isTrue);
    });
  });
}
