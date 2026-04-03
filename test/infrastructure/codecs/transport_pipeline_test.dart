import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/json_payload_size_heuristic.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/infrastructure/codecs/payload_codec.dart';
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

    test('prepareSend keeps cmp none when compression mode is none', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'none',
        compressionThreshold: 1,
      );
      final data = {'message': 'Hello World! ' * 100};
      final frame = pipeline.prepareSend(data).getOrThrow();
      expect(frame.cmp, equals('none'));
      expect(pipeline.receiveProcess(frame).getOrThrow(), equals(data));
    });

    test('receiveProcess accepts List<int> payload bytes', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'none',
      );
      final data = {'x': 1};
      final prepared = pipeline.prepareSend(data).getOrThrow();
      final listPayload = (prepared.payload as Uint8List).toList();
      final frame = PayloadFrame(
        schemaVersion: prepared.schemaVersion,
        enc: prepared.enc,
        cmp: prepared.cmp,
        contentType: prepared.contentType,
        originalSize: prepared.originalSize,
        compressedSize: prepared.compressedSize,
        payload: listPayload,
        traceId: prepared.traceId,
        requestId: prepared.requestId,
      );

      expect(pipeline.receiveProcess(frame).getOrThrow(), equals(data));
    });

    test('receiveProcess fails when payload is not binary', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'none',
      );
      final prepared = pipeline.prepareSend(<String, dynamic>{}).getOrThrow();
      final frame = PayloadFrame(
        schemaVersion: prepared.schemaVersion,
        enc: prepared.enc,
        cmp: prepared.cmp,
        contentType: prepared.contentType,
        originalSize: prepared.originalSize,
        compressedSize: prepared.compressedSize,
        payload: 'not-bytes',
        traceId: prepared.traceId,
        requestId: prepared.requestId,
      );

      expect(pipeline.receiveProcess(frame).isError(), isTrue);
    });

    test('receiveProcess fails when byte length does not match compressedSize', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'none',
      );
      final prepared = pipeline.prepareSend(<String, dynamic>{}).getOrThrow();
      final bytes = prepared.payload as Uint8List;
      final frame = PayloadFrame(
        schemaVersion: prepared.schemaVersion,
        enc: prepared.enc,
        cmp: prepared.cmp,
        contentType: prepared.contentType,
        originalSize: prepared.originalSize,
        compressedSize: bytes.length + 1,
        payload: bytes,
        traceId: prepared.traceId,
        requestId: prepared.requestId,
      );

      expect(pipeline.receiveProcess(frame).isError(), isTrue);
    });

    test('receiveProcess rejects compressed payload above maxCompressedBytes', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'none',
      );
      final prepared = pipeline.prepareSend(<String, dynamic>{}).getOrThrow();
      expect(
        pipeline.receiveProcess(
          prepared,
          maxCompressedBytes: prepared.compressedSize - 1,
        ).isError(),
        isTrue,
      );
    });

    test('receiveProcess rejects frame when originalSize exceeds maxOriginalBytes', () {
      final pipeline = TransportPipeline(
        encoding: 'json',
        compression: 'none',
      );
      final prepared = pipeline.prepareSend(<String, dynamic>{}).getOrThrow();
      expect(
        pipeline.receiveProcess(
          prepared,
          maxOriginalBytes: prepared.originalSize - 1,
        ).isError(),
        isTrue,
      );
    });

    test(
      'receiveProcessAsync fails when gzip decompress throws in isolate path',
      () async {
        final pipeline = TransportPipeline(
          encoding: 'json',
          compression: 'none',
        );
        final invalidGzip = Uint8List(gzipIsolateThresholdBytes);
        final frame = PayloadFrame(
          schemaVersion: '1.0',
          enc: 'json',
          cmp: 'gzip',
          contentType: const JsonPayloadCodec().contentType,
          originalSize: 1,
          compressedSize: invalidGzip.length,
          payload: invalidGzip,
          traceId: 'trace',
        );

        final result = await pipeline.receiveProcessAsync(frame);
        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull()! as CompressionFailure;
        expect(failure.message, contains('decompress'));
        expect(failure.context['operation'], 'decompress');
      },
    );

    test(
      'receiveProcessAsync fails when JSON decode throws in isolate path',
      () async {
        final pipeline = TransportPipeline(
          encoding: 'json',
          compression: 'none',
        );
        final notJsonUtf8 = utf8.encode(
          '{${'x' * (jsonPayloadIsolateEncodeThresholdBytes + 64)}}',
        );
        final bytes = Uint8List.fromList(notJsonUtf8);
        final frame = PayloadFrame(
          schemaVersion: '1.0',
          enc: 'json',
          cmp: 'none',
          contentType: const JsonPayloadCodec().contentType,
          originalSize: bytes.length,
          compressedSize: bytes.length,
          payload: bytes,
          traceId: 'trace',
        );

        final result = await pipeline.receiveProcessAsync(frame);
        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull()! as CompressionFailure;
        expect(failure.message, contains('decode JSON'));
        expect(failure.context['operation'], 'jsonDecode');
      },
    );

    test(
      'prepareSendAsync fails when JSON encode throws in isolate path',
      () async {
        final pipeline = TransportPipeline(
          encoding: 'json',
          compression: 'none',
          compressionThreshold: 1 << 30,
        );
        final data = <String, dynamic>{
          'blob': 'a' * 300000,
          'bad': Object(),
        };

        final result = await pipeline.prepareSendAsync(data);
        expect(result.isError(), isTrue);
        final failure = result.exceptionOrNull()! as CompressionFailure;
        expect(failure.message, contains('encode JSON'));
        expect(failure.context['operation'], 'jsonEncode');
      },
    );
  });
}
