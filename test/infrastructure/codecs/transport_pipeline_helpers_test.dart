import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline_helpers.dart';

void main() {
  group('transport pipeline helpers', () {
    test('shouldRunGzipCompression respects mode and threshold', () {
      expect(shouldRunGzipCompression('none', 10_000, 100), isFalse);
      expect(shouldRunGzipCompression('gzip', 10, 100), isFalse);
      expect(shouldRunGzipCompression('gzip', 200, 100), isTrue);
      expect(shouldRunGzipCompression('auto', 200, 100), isTrue);
    });

    test('exceedsInflationRatio detects oversized expansion', () {
      expect(exceedsInflationRatio(100, 10, 5), isTrue);
      expect(exceedsInflationRatio(40, 10, 5), isFalse);
    });

    test('payloadBytesFromFramePayload normalizes binary inputs', () {
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);
      expect(payloadBytesFromFramePayload(bytes), bytes);
      expect(payloadBytesFromFramePayload(bytes.buffer), isA<Uint8List>());
      expect(payloadBytesFromFramePayload(<int>[4, 5]), Uint8List.fromList(<int>[4, 5]));
      expect(payloadBytesFromFramePayload('text'), isNull);
    });
  });
}
