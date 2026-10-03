import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/external_services/transport/payload_frame_codec.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';
import 'package:plug_agente/infrastructure/security/payload_signer.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

Map<String, dynamic>? _loadCatalog() {
  final fromEnv = Platform.environment['PLUG_SERVER_FIXTURE_DIR'];
  final fixtureDir = (fromEnv != null && fromEnv.isNotEmpty)
      ? fromEnv
      : p.normalize(
          p.join(Directory.current.path, '..', 'plug_server', 'tests', 'fixtures', 'socket'),
        );
  final catalogFile = File(p.join(fixtureDir, 'agent_inbound_catalog.json'));
  if (!catalogFile.existsSync()) {
    if (Platform.environment['REQUIRE_PLUG_SERVER_CONTRACT'] == 'true') {
      throw StateError('Required plug_server catalog is unavailable: ${catalogFile.path}');
    }
    return null;
  }
  return jsonDecode(catalogFile.readAsStringSync()) as Map<String, dynamic>;
}

PayloadFrameCodec buildCodec({
  required ProtocolConfig protocol,
  PayloadSigner? payloadSigner,
  bool localShouldSignOutgoing = false,
}) {
  final flags = _MockFeatureFlags();
  when(() => flags.outboundCompressionMode).thenReturn(
    protocol.compression == 'gzip' ? OutboundCompressionMode.gzip : OutboundCompressionMode.none,
  );
  when(() => flags.compressionThreshold).thenReturn(protocol.compressionThreshold);
  final cache = TransportPipelineCache(
    protocolProvider: () => protocol,
    hasReceivedCapabilities: () => true,
    featureFlags: flags,
  );
  return PayloadFrameCodec(
    pipelineCache: cache,
    protocolProvider: () => protocol,
    localCapabilitiesProvider: ProtocolCapabilities.defaultCapabilities,
    hasReceivedCapabilities: () => true,
    localShouldSignOutgoing: () => localShouldSignOutgoing,
    localRequiresIncomingSignature: () => false,
    payloadSigner: payloadSigner,
  );
}

void main() {
  test('codec accepts hub inbound catalog bodies for none, gzip, HMAC and stream frames', () async {
    final catalog = _loadCatalog();
    if (catalog == null) {
      markTestSkipped(
        'plug_server catalog not found; set PLUG_SERVER_FIXTURE_DIR or keep ../plug_server/tests/fixtures/socket',
      );
      return;
    }

    final frames = Map<String, dynamic>.from(catalog['frames'] as Map);
    final hmacTestKey = catalog['hmacTestKey'] as String;
    final hmacKeyId = catalog['hmacKeyId'] as String;
    expect(hmacTestKey, isNotEmpty);
    expect(hmacKeyId, isNotEmpty);

    final noneCodec = buildCodec(
      protocol: const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'none',
        compressionThreshold: 1 << 30,
      ),
    );
    final gzipCodec = buildCodec(
      protocol: const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'gzip',
        compressionThreshold: 1,
      ),
    );
    final hmacCodec = buildCodec(
      protocol: const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'none',
        compressionThreshold: 1 << 30,
        signatureAlgorithms: ['hmac-sha256'],
      ),
      localShouldSignOutgoing: true,
      payloadSigner: PayloadSigner(keys: {hmacKeyId: hmacTestKey}),
    );

    expect(noneCodec.looksLikePayloadFrame(frames['invalidFrameBody']), isFalse);

    const skipEncode = {'invalidFrameBody', 'oversizeHint'};
    for (final entry in frames.entries) {
      if (skipEncode.contains(entry.key)) {
        continue;
      }
      final body = entry.value;
      final noneWire = (await noneCodec.prepareOutgoing(
        event: 'rpc:response',
        logicalPayload: body,
      )).getOrThrow();
      expect(noneWire['cmp'], 'none');
      expect(noneCodec.decodeIncoming(noneWire).getOrThrow(), body);

      final gzipWire = (await gzipCodec.prepareOutgoing(
        event: 'rpc:response',
        logicalPayload: body,
      )).getOrThrow();
      expect(gzipWire['cmp'], 'gzip');
      expect(gzipCodec.decodeIncoming(gzipWire).getOrThrow(), body);
    }

    final hmacWire = (await hmacCodec.prepareOutgoing(
      event: 'rpc:response',
      logicalPayload: frames['unaryResponse'],
    )).getOrThrow();
    expect(hmacWire['signature'], isA<Map<String, dynamic>>());
    expect((hmacWire['signature'] as Map)['key_id'], hmacKeyId);
    expect(hmacCodec.decodeIncoming(hmacWire).getOrThrow(), frames['unaryResponse']);

    for (final name in ['streamOpen', 'streamChunk', 'streamComplete']) {
      final body = frames[name];
      final wire = (await noneCodec.prepareOutgoing(
        event: name == 'streamOpen' ? 'rpc:response' : (name == 'streamChunk' ? 'rpc:chunk' : 'rpc:complete'),
        logicalPayload: body,
      )).getOrThrow();
      expect(noneCodec.looksLikePayloadFrame(wire), isTrue);
      expect(noneCodec.decodeIncoming(wire).getOrThrow(), body);
    }
  });
}
