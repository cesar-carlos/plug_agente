import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/core/config/outbound_compression_mode.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/external_services/transport/transport_pipeline_cache.dart';

class _MockFeatureFlags extends Mock implements FeatureFlags {}

PayloadFrame _frame({
  required String enc,
  required String cmp,
  String schemaVersion = 'payload-frame/1.0',
}) {
  return PayloadFrame(
    schemaVersion: schemaVersion,
    enc: enc,
    cmp: cmp,
    contentType: 'application/json',
    payload: 'aGVsbG8=',
    originalSize: 5,
    compressedSize: 5,
  );
}

void main() {
  late _MockFeatureFlags featureFlags;
  late ProtocolConfig protocol;
  late bool hasCaps;

  setUp(() {
    featureFlags = _MockFeatureFlags();
    when(() => featureFlags.outboundCompressionMode).thenReturn(OutboundCompressionMode.auto);
    when(() => featureFlags.compressionThreshold).thenReturn(2048);
    protocol = const ProtocolConfig(
      protocol: 'jsonrpc-v2',
      encoding: 'json',
      compression: 'gzip',
    );
    hasCaps = true;
  });

  TransportPipelineCache build({int maxReceive = 4}) {
    return TransportPipelineCache(
      protocolProvider: () => protocol,
      hasReceivedCapabilities: () => hasCaps,
      featureFlags: featureFlags,
      maxReceiveEntries: maxReceive,
    );
  }

  group('TransportPipelineCache.send', () {
    test('returns the same instance when configuration is unchanged', () {
      final cache = build();
      final first = cache.send();
      final second = cache.send();
      expect(identical(first, second), isTrue);
    });

    test('rebuilds when negotiated protocol changes', () {
      final cache = build();
      final first = cache.send();
      protocol = const ProtocolConfig(
        protocol: 'jsonrpc-v2',
        encoding: 'json',
        compression: 'none',
      );
      final second = cache.send();
      expect(identical(first, second), isFalse);
    });

    test('rebuilds when feature flag toggles compression mode', () {
      final cache = build();
      final first = cache.send();
      when(() => featureFlags.outboundCompressionMode).thenReturn(OutboundCompressionMode.none);
      final second = cache.send();
      expect(identical(first, second), isFalse);
    });

    test('reset() forces a rebuild on next access', () {
      final cache = build();
      final first = cache.send();
      cache.reset();
      final second = cache.send();
      expect(identical(first, second), isFalse);
    });
  });

  group('TransportPipelineCache.receive', () {
    test('caches the pipeline per frame envelope key', () {
      final cache = build();
      final frame = _frame(enc: 'json', cmp: 'gzip');

      final first = cache.receive(frame);
      final second = cache.receive(frame);

      expect(identical(first, second), isTrue);
      expect(cache.receiveCacheSize, 1);
    });

    test('different envelopes get different pipeline instances', () {
      final cache = build();
      final a = cache.receive(_frame(enc: 'json', cmp: 'gzip'));
      final b = cache.receive(_frame(enc: 'json', cmp: 'none'));
      expect(identical(a, b), isFalse);
      expect(cache.receiveCacheSize, 2);
    });

    test('evicts the oldest entry when exceeding the cap (LRU)', () {
      final cache = build(maxReceive: 2);
      cache.receive(_frame(enc: 'json', cmp: 'gzip'));
      cache.receive(_frame(enc: 'cbor', cmp: 'gzip'));
      cache.receive(_frame(enc: 'json', cmp: 'none'));

      expect(cache.receiveCacheSize, 2);
      final keys = cache.receiveCacheKeys.toList();
      expect(keys.any((k) => k.startsWith('json|gzip|')), isFalse);
    });

    test('promoting a hit moves it to the end of the LRU window', () {
      final cache = build(maxReceive: 2);
      final first = _frame(enc: 'json', cmp: 'gzip');
      cache.receive(first);
      cache.receive(_frame(enc: 'cbor', cmp: 'gzip'));

      cache.receive(first);
      cache.receive(_frame(enc: 'json', cmp: 'none'));

      final keys = cache.receiveCacheKeys.toList();
      expect(keys.any((k) => k.startsWith('json|gzip|')), isTrue);
      expect(keys.any((k) => k.startsWith('cbor|gzip|')), isFalse);
    });

    test('clearReceiveCache empties the receive cache only', () {
      final cache = build();
      cache.send();
      cache.receive(_frame(enc: 'json', cmp: 'gzip'));

      cache.clearReceiveCache();

      expect(cache.receiveCacheSize, 0);
      final reused = cache.send();
      final reusedAgain = cache.send();
      expect(identical(reused, reusedAgain), isTrue);
    });
  });
}
