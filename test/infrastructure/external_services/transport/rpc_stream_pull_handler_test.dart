import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/rpc_stream_pull_handler.dart';
import 'package:plug_agente/infrastructure/validation/rpc_contract_validator.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

class _MockPayloadFrameCodec extends Mock implements PayloadFrameCodec {}

void main() {
  group('RpcStreamPullHandler schema validation', () {
    late _MockFeatureFlags featureFlags;
    late List<({String event, Map<String, dynamic> payload})> emitted;

    setUp(() {
      featureFlags = _MockFeatureFlags();
      emitted = <({String event, Map<String, dynamic> payload})>[];
      when(() => featureFlags.enableSocketBackpressure).thenReturn(false);
      when(() => featureFlags.enableSocketSchemaValidation).thenReturn(true);
    });

    RpcStreamPullHandler createHandler() {
      return RpcStreamPullHandler(
        featureFlags: featureFlags,
        frameCodec: _MockPayloadFrameCodec(),
        contractValidator: const RpcContractValidator(),
        protocolProvider: () => const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'none',
        ),
        emitEventAsync: (event, payload) async {
          emitted.add((event: event, payload: payload as Map<String, dynamic>));
          return true;
        },
        logMessage: (_, _, _) {},
      );
    }

    test('should validate rpc:chunk schema for every chunk index', () async {
      final handler = createHandler();
      final emitter = handler.createStreamEmitter();

      await emitter.emitChunk(
        RpcStreamChunk(
          streamId: 's-1',
          requestId: 'req-1',
          chunkIndex: 0,
          rows: const [
            {'id': 1},
          ],
          columnMetadata: const [
            {'name': 'id'},
          ],
        ),
      );
      await emitter.emitChunk(
        RpcStreamChunk(
          streamId: 's-1',
          requestId: 'req-1',
          chunkIndex: 1,
          rows: const [
            {'id': 2},
          ],
        ),
      );

      expect(emitted, hasLength(2));
      expect(emitted[0].payload['chunk_index'], 0);
      expect(emitted[0].payload['column_metadata'], isNotNull);
      expect(emitted[1].payload['chunk_index'], 1);
      expect(emitted[1].payload, isNot(contains('column_metadata')));
    });

    test('should reject invalid chunk 0 payloads', () async {
      final handler = createHandler();
      final emitter = handler.createStreamEmitter();

      final accepted = await emitter.emitChunk(
        RpcStreamChunk(
          streamId: '',
          requestId: 'req-1',
          chunkIndex: 0,
          rows: const [],
        ),
      );

      expect(accepted, isFalse);
      expect(emitted, isEmpty);
    });
  });

  group('RpcStreamPullHandler backpressure', () {
    late _MockFeatureFlags featureFlags;

    setUp(() {
      featureFlags = _MockFeatureFlags();
    });

    test('uses recommended pull window as initial send credit', () async {
      when(() => featureFlags.enableSocketBackpressure).thenReturn(true);
      when(() => featureFlags.enableSocketSchemaValidation).thenReturn(false);

      final handler = RpcStreamPullHandler(
        featureFlags: featureFlags,
        frameCodec: _MockPayloadFrameCodec(),
        contractValidator: const RpcContractValidator(),
        protocolProvider: () => const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'none',
        ),
        emitEventAsync: (_, payload) async {
          return true;
        },
        logMessage: (_, _, _) {},
      );
      final emitter = handler.createStreamEmitter();

      for (var i = 0; i < 8; i++) {
        final accepted = await emitter.emitChunk(
          RpcStreamChunk(
            streamId: 's-bp',
            requestId: 'req-bp',
            chunkIndex: i,
            rows: [
              {'id': i},
            ],
          ),
        );
        expect(accepted, isTrue, reason: 'chunk $i');
      }
    });
  });
}
