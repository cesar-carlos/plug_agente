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

class _MockFeatureFlags extends Mock implements FeatureFlags {}

void main() {
  PayloadFrameCodec buildCodec({
    required ProtocolConfig protocol,
    bool hasCaps = true,
    bool localSignatureRequired = false,
  }) {
    final flags = _MockFeatureFlags();
    when(() => flags.outboundCompressionMode).thenReturn(OutboundCompressionMode.auto);
    when(() => flags.compressionThreshold).thenReturn(2048);
    final cache = TransportPipelineCache(
      protocolProvider: () => protocol,
      hasReceivedCapabilities: () => hasCaps,
      featureFlags: flags,
    );
    return PayloadFrameCodec(
      pipelineCache: cache,
      protocolProvider: () => protocol,
      localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
      hasReceivedCapabilities: () => hasCaps,
      localSignatureRequired: () => localSignatureRequired,
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
  });
}
