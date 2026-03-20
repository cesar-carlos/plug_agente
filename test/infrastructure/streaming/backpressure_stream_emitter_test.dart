import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/streaming/backpressure_stream_emitter.dart';

void main() {
  group('BackpressureStreamEmitter', () {
    late List<({String event, Map<String, dynamic> payload})> emitted;

    BackpressureStreamEmitter createEmitter({
      void Function(String streamId, BackpressureStreamEmitter)? onRegister,
      void Function(String streamId)? onUnregister,
    }) {
      emitted = [];
      return BackpressureStreamEmitter(
        emit: (event, payload) => emitted.add((event: event, payload: payload)),
        onRegister: onRegister ?? (_, _) {},
        onUnregister: onUnregister ?? (_) {},
      );
    }

    test('should emit first chunk immediately with initial credit 1', () {
      final emitter = createEmitter();

      emitter.emitChunk(
        const RpcStreamChunk(
          streamId: 's-1',
          requestId: 'req-1',
          chunkIndex: 0,
          rows: [
            {'id': 1},
          ],
        ),
      );

      check(emitted).length.equals(1);
      check(emitted.first.event).equals('rpc:chunk');
      check(emitted.first.payload['chunk_index']).equals(0);
    });

    test(
      'should queue chunks when credit exhausted and emit after releaseChunks',
      () {
        final emitter = createEmitter();

        emitter.emitChunk(
          const RpcStreamChunk(
            streamId: 's-1',
            requestId: 'req-1',
            chunkIndex: 0,
            rows: [
              {'id': 1},
            ],
          ),
        );
        emitter.emitChunk(
          const RpcStreamChunk(
            streamId: 's-1',
            requestId: 'req-1',
            chunkIndex: 1,
            rows: [
              {'id': 2},
            ],
          ),
        );
        emitter.emitChunk(
          const RpcStreamChunk(
            streamId: 's-1',
            requestId: 'req-1',
            chunkIndex: 2,
            rows: [
              {'id': 3},
            ],
          ),
        );

        check(emitted).length.equals(1);
        check(emitted.first.payload['chunk_index']).equals(0);

        emitter.releaseChunks(2);

        check(emitted).length.equals(3);
        check(emitted[1].payload['chunk_index']).equals(1);
        check(emitted[2].payload['chunk_index']).equals(2);
      },
    );

    test('should emit complete only after all chunks sent', () {
      final emitter = createEmitter();

      emitter.emitChunk(
        const RpcStreamChunk(
          streamId: 's-1',
          requestId: 'req-1',
          chunkIndex: 0,
          rows: [
            {'id': 1},
          ],
        ),
      );
      emitter.emitChunk(
        const RpcStreamChunk(
          streamId: 's-1',
          requestId: 'req-1',
          chunkIndex: 1,
          rows: [
            {'id': 2},
          ],
        ),
      );
      emitter.emitComplete(
        const RpcStreamComplete(
          streamId: 's-1',
          requestId: 'req-1',
          totalRows: 2,
        ),
      );

      check(emitted).length.equals(1);
      check(emitted.first.event).equals('rpc:chunk');

      emitter.releaseChunks(1);

      check(emitted).length.equals(3);
      check(emitted[1].event).equals('rpc:chunk');
      check(emitted[2].event).equals('rpc:complete');
      check(emitted[2].payload['total_rows']).equals(2);
    });

    test(
      'should call onRegister on first chunk and onUnregister after complete',
      () {
        var registeredId = '';
        var unregisteredId = '';
        final emitter = createEmitter(
          onRegister: (id, _) => registeredId = id,
          onUnregister: (id) => unregisteredId = id,
        );

        emitter.emitChunk(
          const RpcStreamChunk(
            streamId: 's-1',
            requestId: 'req-1',
            chunkIndex: 0,
            rows: [
              {'id': 1},
            ],
          ),
        );
        check(registeredId).equals('s-1');
        check(unregisteredId).equals('');

        emitter.emitComplete(
          const RpcStreamComplete(
            streamId: 's-1',
            requestId: 'req-1',
            totalRows: 1,
          ),
        );
        check(unregisteredId).equals('s-1');
      },
    );

    test('should return false on buffer overflow instead of dropping chunks', () {
      createEmitter();
      const maxSize = 5;
      // Small maxQueueSize exercises overflow without emitting 1000+ chunks.
      final emitterWithSmallLimit = BackpressureStreamEmitter(
        emit: (event, payload) => emitted.add((event: event, payload: payload)),
        onRegister: (_, _) {},
        onUnregister: (_) {},
        maxQueueSize: maxSize,
      );
      emitted = [];
      // Exhaust initial credit with one chunk
      emitterWithSmallLimit.emitChunk(
        const RpcStreamChunk(
          streamId: 's-1',
          requestId: 'req-1',
          chunkIndex: 0,
          rows: [
            {'id': 1},
          ],
        ),
      );
      check(emitted).length.equals(1);
      // Now queue is empty, credit 0. Fill queue to maxSize without releasing.
      for (var i = 1; i <= maxSize; i++) {
        final accepted = emitterWithSmallLimit.emitChunk(
          RpcStreamChunk(
            streamId: 's-1',
            requestId: 'req-1',
            chunkIndex: i,
            rows: [
              {'id': i},
            ],
          ),
        );
        check(accepted).isTrue();
      }
      // Next chunk should overflow
      final overflowed = emitterWithSmallLimit.emitChunk(
        const RpcStreamChunk(
          streamId: 's-1',
          requestId: 'req-1',
          chunkIndex: maxSize + 1,
          rows: [
            {'id': 999},
          ],
        ),
      );
      check(overflowed).isFalse();
      // No additional chunks should have been emitted (still 1 from initial)
      check(emitted).length.equals(1);
    });

    test('should ignore releaseChunks with windowSize <= 0', () {
      final emitter = createEmitter();

      emitter.emitChunk(
        const RpcStreamChunk(
          streamId: 's-1',
          requestId: 'req-1',
          chunkIndex: 0,
          rows: [
            {'id': 1},
          ],
        ),
      );
      emitter.emitChunk(
        const RpcStreamChunk(
          streamId: 's-1',
          requestId: 'req-1',
          chunkIndex: 1,
          rows: [
            {'id': 2},
          ],
        ),
      );

      emitter.releaseChunks(0);
      check(emitted).length.equals(1);

      emitter.releaseChunks(-1);
      check(emitted).length.equals(1);
    });
  });
}
