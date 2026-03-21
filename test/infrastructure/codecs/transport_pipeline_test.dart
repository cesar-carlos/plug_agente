import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:plug_agente/infrastructure/codecs/payload_frame.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('TransportPipeline', () {
    test('should prepare payload without compression when below threshold', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'gzip',
        compressionThreshold: 1000,
      );

      final data = {'message': 'Hello'};

      final result = pipeline.prepareSend(data);

      expect(result.isSuccess(), isTrue);
      final frame = result.getOrThrow();
      expect(frame.cmp, equals('none'));
      expect(frame.enc, equals('json'));
      expect(frame.compressedSize, equals(frame.originalSize));
    });

    test('should prepare payload with compression when above threshold', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'gzip',
        compressionThreshold: 50,
      );

      final data = {'message': 'Hello World! ' * 100};

      final result = pipeline.prepareSend(data);

      expect(result.isSuccess(), isTrue);
      final frame = result.getOrThrow();
      expect(frame.cmp, equals('gzip'));
      expect(frame.compressedSize, lessThan(frame.originalSize));
    });

    test('auto mode compresses repetitive payloads when beneficial', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'auto',
        compressionThreshold: 50,
      );

      final data = {'message': 'Hello World! ' * 100};
      final result = pipeline.prepareSend(data);

      expect(result.isSuccess(), isTrue);
      final frame = result.getOrThrow();
      expect(frame.cmp, equals('gzip'));
      expect(frame.compressedSize, lessThan(frame.originalSize));
      expect(pipeline.receiveProcess(frame).getOrThrow(), equals(data));
    });

    test(
      'auto mode uses cmp none when gzip does not shrink payload',
      () {
        final pipeline = TransportPipeline(
          encoding: 'json',
          compression: 'auto',
          compressionThreshold: 1,
        );

        final data = {'a': 'x'};
        final result = pipeline.prepareSend(data);
        expect(result.isSuccess(), isTrue);
        final frame = result.getOrThrow();
        expect(frame.cmp, equals('none'));
        expect(frame.compressedSize, equals(frame.originalSize));
        expect(pipeline.receiveProcess(frame).getOrThrow(), equals(data));
      },
    );

    test('should process received frame without compression', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'gzip',
      );

      final originalData = {'message': 'Hello'};
      final frame = pipeline.prepareSend(originalData).getOrThrow();

      final result = pipeline.receiveProcess(frame);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), equals(originalData));
    });

    test('should process received frame with compression', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'gzip',
        compressionThreshold: 10,
      );

      final originalData = {'message': 'Hello World! ' * 100};
      final frame = pipeline.prepareSend(originalData).getOrThrow();

      expect(frame.cmp, equals('gzip'));

      final result = pipeline.receiveProcess(frame);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow(), equals(originalData));
    });

    test('should handle round-trip with compression', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'gzip',
        compressionThreshold: 50,
      );

      final originalData = {
        'users': List.generate(
          100,
          (i) => {'id': i, 'name': 'User $i', 'email': 'user$i@example.com'},
        ),
      };

      final prepareResult = pipeline.prepareSend(originalData);
      expect(prepareResult.isSuccess(), isTrue);

      final frame = prepareResult.getOrThrow();
      expect(frame.cmp, equals('gzip'));
      expect(frame.compressedSize, lessThan(frame.originalSize));

      final receiveResult = pipeline.receiveProcess(frame);
      expect(receiveResult.isSuccess(), isTrue);
      expect(receiveResult.getOrThrow(), equals(originalData));
    });

    test('should return failure when frame encoding mismatches', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'none',
      );

      final frameBytes = Uint8List.fromList(utf8.encode('{"test": "data"}'));
      final invalidFrame = pipeline.frameFromBytes(frameBytes);

      final pipeline2 = TransportPipeline(
        encoding: 'msgpack',
        compression: 'none',
      );

      final result = pipeline2.receiveProcess(invalidFrame);

      expect(result.isError(), isTrue);
    });

    test('should include trace ID in prepared frame', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'none',
      );

      final data = {'message': 'test'};
      const traceId = 'trace-123';

      final result = pipeline.prepareSend(data, traceId: traceId);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().traceId, equals(traceId));
    });

    test('should reject payload inflation beyond configured ratio', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'gzip',
        compressionThreshold: 1,
      );

      final originalData = {'message': 'Hello World! ' * 100};
      final frame = pipeline.prepareSend(originalData).getOrThrow();

      final result = pipeline.receiveProcess(
        frame,
        maxInflationRatio: 1.1,
      );

      expect(result.isError(), isTrue);
    });

    test(
      'receiveProcessAsync should match receiveProcess for gzip frames',
      () async {
        final pipeline = TransportPipeline(
          encoding: 'json',
          compression: 'gzip',
          compressionThreshold: 10,
        );

        final originalData = {'message': 'Hello World! ' * 100};
        final frame = pipeline.prepareSend(originalData).getOrThrow();
        expect(frame.cmp, equals('gzip'));

        final syncResult = pipeline.receiveProcess(frame);
        final asyncResult = await pipeline.receiveProcessAsync(frame);

        expect(syncResult.isSuccess(), isTrue);
        expect(asyncResult.isSuccess(), isTrue);
        expect(asyncResult.getOrThrow(), equals(syncResult.getOrThrow()));
      },
    );

    test(
      'receiveProcessAsync decodes large JSON via isolate when above threshold',
      () async {
        final pipeline = TransportPipeline(
          encoding: 'json',
          compression: 'none',
        );
        final pad = 'z' * (jsonPayloadIsolateEncodeThresholdBytes + 4096);
        final originalData = <String, dynamic>{'blob': pad};
        final frame = pipeline.prepareSend(originalData).getOrThrow();
        expect(
          frame.compressedSize,
          greaterThan(jsonPayloadIsolateEncodeThresholdBytes),
        );
        final asyncResult = await pipeline.receiveProcessAsync(frame);
        expect(asyncResult.isSuccess(), isTrue);
        expect(asyncResult.getOrThrow(), equals(originalData));

        final syncResult = pipeline.receiveProcess(frame);
        expect(syncResult.isSuccess(), isTrue);
        expect(syncResult.getOrThrow(), equals(originalData));
      },
    );

    test(
      'prepareSendAsync encodes large JSON via isolate path',
      () async {
        final pipeline = TransportPipeline(
          encoding: 'json',
          compression: 'none',
          compressionThreshold: 999999999,
        );
        final huge = <String, dynamic>{'blob': 'a' * 200000};
        final result = await pipeline.prepareSendAsync(huge);
        expect(result.isSuccess(), isTrue);
        final frame = result.getOrThrow();
        expect(frame.cmp, equals('none'));
        expect(pipeline.receiveProcess(frame).getOrThrow(), equals(huge));
      },
    );
  });

  group('incomingPayloadFrameNeedsAsyncDecode', () {
    PayloadFrame frame({
      required String cmp,
      required int compressedSize,
      required int originalSize,
    }) {
      return PayloadFrame(
        schemaVersion: '1.0',
        enc: 'json',
        cmp: cmp,
        contentType: 'application/json',
        originalSize: originalSize,
        compressedSize: compressedSize,
        payload: Uint8List(compressedSize),
      );
    }

    test('false for small uncompressed JSON', () {
      expect(
        incomingPayloadFrameNeedsAsyncDecode(
          frame(
            cmp: 'none',
            compressedSize: 100,
            originalSize: 100,
          ),
        ),
        isFalse,
      );
    });

    test('true when uncompressed JSON at isolate decode threshold', () {
      expect(
        incomingPayloadFrameNeedsAsyncDecode(
          frame(
            cmp: 'none',
            compressedSize: jsonPayloadIsolateEncodeThresholdBytes,
            originalSize: jsonPayloadIsolateEncodeThresholdBytes,
          ),
        ),
        isTrue,
      );
    });

    test('true when gzip compressed blob is large', () {
      expect(
        incomingPayloadFrameNeedsAsyncDecode(
          frame(
            cmp: 'gzip',
            compressedSize: gzipIsolateThresholdBytes,
            originalSize: gzipIsolateThresholdBytes * 10,
          ),
        ),
        isTrue,
      );
    });

    test(
      'true when gzip wire is small but declared original is large',
      () {
        expect(
          incomingPayloadFrameNeedsAsyncDecode(
            frame(
              cmp: 'gzip',
              compressedSize: 1024,
              originalSize: gzipIsolateThresholdBytes,
            ),
          ),
          isTrue,
        );
      },
    );

    test('unknown compression requests async path', () {
      expect(
        incomingPayloadFrameNeedsAsyncDecode(
          frame(
            cmp: 'lz4',
            compressedSize: 10,
            originalSize: 10,
          ),
        ),
        isTrue,
      );
    });
  });
}
