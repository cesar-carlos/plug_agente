import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';
import 'package:plug_agente/infrastructure/metrics/protocol_metrics.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

void main() {
  PayloadFrameCodec buildCodec({
    required ProtocolConfig protocol,
    bool hasCaps = true,
    bool localShouldSignOutgoing = false,
    bool localRequiresIncomingSignature = false,
    PayloadSigner? payloadSigner,
    ProtocolMetricsCollector? metricsCollector,
  }) {
    final flags = _MockFeatureFlags();
    when(() => flags.outboundCompressionMode).thenReturn(OutboundCompressionMode.auto);
    when(() => flags.compressionThreshold).thenReturn(2048);
    final cache = TransportPipelineCache(
      protocolProvider: () => protocol,
      hasReceivedCapabilities: () => hasCaps,
      featureFlags: flags,
      metricsCollector: metricsCollector,
    );
    return PayloadFrameCodec(
      pipelineCache: cache,
      protocolProvider: () => protocol,
      localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
      hasReceivedCapabilities: () => hasCaps,
      localShouldSignOutgoing: () => localShouldSignOutgoing,
      localRequiresIncomingSignature: () => localRequiresIncomingSignature,
      payloadSigner: payloadSigner,
      metricsCollector: metricsCollector,
    );
  }

  group('PayloadFrameCodec.looksLikePayloadFrame', () {
    test('detects a frame envelope by required fields', () {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
      );
      final frame = TransportPipeline(
        encoding: 'json',
        compression: 'gzip',
      ).prepareSend({'foo': 'bar'}).getOrThrow().toJson();
      expect(codec.looksLikePayloadFrame(frame), isTrue);
    });

    test('returns false for raw rpc payloads', () {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
      );
      expect(
        codec.looksLikePayloadFrame({'jsonrpc': '2.0', 'id': 1, 'method': 'x'}),
        isFalse,
      );
    });

    test('returns false for non-map payloads', () {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
      );
      expect(codec.looksLikePayloadFrame('not a map'), isFalse);
      expect(codec.looksLikePayloadFrame(null), isFalse);
      expect(codec.looksLikePayloadFrame(42), isFalse);
    });
  });

  group('PayloadFrameCodec.prepareOutgoing + decodeIncoming', () {
    test('round-trips a payload through frame and back', () async {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
      );
      final original = <String, dynamic>{
        'jsonrpc': '2.0',
        'id': 'req-1',
        'method': 'sql.execute',
        'params': {'sql': 'SELECT 1'},
      };

      final wire = await codec.prepareOutgoing(
        event: 'rpc:request',
        logicalPayload: original,
      );

      expect(wire, isNotNull);
      expect(codec.looksLikePayloadFrame(wire), isTrue);

      final decoded = codec.decodeIncoming(wire);
      expect(decoded, original);
    });

    test('async decode returns the same payload as sync decode', () async {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
      );
      final original = <String, dynamic>{'a': 1, 'b': 'two'};

      final wire = await codec.prepareOutgoing(
        event: 'rpc:request',
        logicalPayload: original,
      );

      final decodedSync = codec.decodeIncoming(wire);
      final decodedAsync = await codec.decodeIncomingAsync(wire);
      expect(decodedSync, decodedAsync);
    });
  });

  group('PayloadFrameCodec.decodeIncoming - validation', () {
    test('throws when payload is not a frame', () {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
      );
      expect(
        () => codec.decodeIncoming({'jsonrpc': '2.0', 'id': 1}),
        throwsA(isA<domain.ValidationFailure>()),
      );
    });

    test('throws when frame uses unsupported encoding', () {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
      );
      final frameJson = const PayloadFrame(
        schemaVersion: 'payload-frame/1.0',
        enc: 'unsupported-format',
        cmp: 'none',
        contentType: 'application/json',
        payload: 'aGVsbG8=',
        originalSize: 5,
        compressedSize: 5,
      ).toJson();

      expect(
        () => codec.decodeIncoming(frameJson),
        throwsA(isA<domain.ValidationFailure>()),
      );
    });

    test('throws when frame uses unsupported compression', () {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
      );
      final frameJson = const PayloadFrame(
        schemaVersion: 'payload-frame/1.0',
        enc: 'json',
        cmp: 'unsupported-codec',
        contentType: 'application/json',
        payload: 'aGVsbG8=',
        originalSize: 5,
        compressedSize: 5,
      ).toJson();

      expect(
        () => codec.decodeIncoming(frameJson),
        throwsA(isA<domain.ValidationFailure>()),
      );
    });
  });

  group('PayloadFrameCodec.shouldSignTransportFrames', () {
    test('returns false when no signer is configured', () {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          signatureRequired: true,
        ),
      );
      expect(codec.shouldSignTransportFrames, isFalse);
    });

    test('signs outgoing frames after shared signature algorithm is negotiated', () async {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          signatureAlgorithms: ['hmac-sha256'],
        ),
        localShouldSignOutgoing: true,
        payloadSigner: PayloadSigner(keys: {'key-1': 'secret'}),
      );

      final wire = await codec.prepareOutgoing(
        event: 'rpc:response',
        logicalPayload: {'id': 'req-1', 'result': true},
      );

      expect(codec.shouldSignTransportFrames, isTrue);
      expect(wire?['signature'], isA<Map<String, dynamic>>());
    });

    test('does not sign optional outgoing frames before capabilities are received', () async {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
        hasCaps: false,
        localShouldSignOutgoing: true,
        payloadSigner: PayloadSigner(keys: {'key-1': 'secret'}),
      );

      final wire = await codec.prepareOutgoing(
        event: 'agent:register',
        logicalPayload: {'agentId': 'agent-1'},
      );

      expect(codec.shouldSignTransportFrames, isFalse);
      expect(wire?['signature'], isNull);
    });

    test('does not sign optional outgoing frames when no signature algorithm is negotiated', () async {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
        localShouldSignOutgoing: true,
        payloadSigner: PayloadSigner(keys: {'key-1': 'secret'}),
      );

      final wire = await codec.prepareOutgoing(
        event: 'rpc:response',
        logicalPayload: {'id': 'req-1', 'result': true},
      );

      expect(codec.shouldSignTransportFrames, isFalse);
      expect(wire?['signature'], isNull);
    });

    test('signs before capabilities only when local inbound signatures are required', () async {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
        hasCaps: false,
        localShouldSignOutgoing: true,
        localRequiresIncomingSignature: true,
        payloadSigner: PayloadSigner(keys: {'key-1': 'secret'}),
      );

      final wire = await codec.prepareOutgoing(
        event: 'agent:register',
        logicalPayload: {'agentId': 'agent-1'},
      );

      expect(codec.shouldSignTransportFrames, isTrue);
      expect(wire?['signature'], isA<Map<String, dynamic>>());
    });

    test('does not require inbound signature before negotiation when only outgoing signing is enabled', () {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
        hasCaps: false,
        localShouldSignOutgoing: true,
        payloadSigner: PayloadSigner(keys: {'key-1': 'secret'}),
      );
      final frame = TransportPipeline(
        encoding: 'json',
        compression: 'gzip',
      ).prepareSend({'capabilities': ProtocolCapabilities.defaultCapabilities().toJson()}).getOrThrow();

      final decoded = codec.decodeIncoming(frame.toJson());

      expect(decoded, isA<Map<String, dynamic>>());
    });

    test('rejects unsigned inbound frames after negotiated signature is required', () {
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          signatureRequired: true,
        ),
        payloadSigner: PayloadSigner(keys: {'key-1': 'secret'}),
      );
      final frame = TransportPipeline(
        encoding: 'json',
        compression: 'gzip',
      ).prepareSend({'id': 'req-1', 'method': 'sql.execute'}).getOrThrow();

      expect(
        () => codec.decodeIncoming(frame.toJson()),
        throwsA(isA<domain.ValidationFailure>()),
      );
    });

    test('rejects signed inbound frames when no signer is configured', () async {
      final signer = PayloadSigner(keys: {'key-1': 'secret'});
      final signedCodec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          signatureAlgorithms: ['hmac-sha256'],
        ),
        localShouldSignOutgoing: true,
        payloadSigner: signer,
      );
      final verifyingCodec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
        ),
      );
      final wire = await signedCodec.prepareOutgoing(
        event: 'rpc:response',
        logicalPayload: {'id': 'req-1', 'result': true},
      );

      expect(
        () => verifyingCodec.decodeIncoming(wire),
        throwsA(isA<domain.ValidationFailure>()),
      );
    });

    test('records runtime signing and verification metrics', () async {
      final collector = ProtocolMetricsCollector();
      final signer = PayloadSigner(keys: {'key-1': 'secret'});
      final codec = buildCodec(
        protocol: const ProtocolConfig(
          protocol: 'jsonrpc-v2',
          encoding: 'json',
          compression: 'gzip',
          signatureAlgorithms: ['hmac-sha256'],
        ),
        localShouldSignOutgoing: true,
        payloadSigner: signer,
        metricsCollector: collector,
      );

      final wire = await codec.prepareOutgoing(
        event: 'rpc:response',
        logicalPayload: {'id': 'req-1', 'result': true},
      );
      final decoded = codec.decodeIncoming(wire, sourceEvent: 'rpc:request');

      expect(decoded, {'id': 'req-1', 'result': true});
      expect(
        collector.metrics.map((ProtocolMetrics metric) => metric.direction),
        containsAll(<String>['sign', 'verify']),
      );
      final signMetric = collector.metrics.firstWhere(
        (ProtocolMetrics metric) => metric.direction == 'sign',
      );
      final verifyMetric = collector.metrics.firstWhere(
        (ProtocolMetrics metric) => metric.direction == 'verify',
      );
      expect(signMetric.signDurationUs, isNotNull);
      expect(signMetric.canonicalizeDurationUs, isNotNull);
      expect(verifyMetric.verifyDurationUs, isNotNull);
      expect(verifyMetric.canonicalizeDurationUs, isNotNull);
    });
  });
}
