import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/codecs/transport_pipeline.dart';

void main() {
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
  });
}
