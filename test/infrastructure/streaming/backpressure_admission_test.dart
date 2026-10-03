import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/protocol.dart';
import 'package:plug_agente/infrastructure/streaming/backpressure_stream_emitter.dart';

RpcStreamChunk chunk(int index) => RpcStreamChunk(
  streamId: 's',
  requestId: 'r',
  chunkIndex: index,
  rows: [
    {'n': index},
  ],
);

void main() {
  test('slow wire emit cannot admit concurrent chunks above the queue ceiling', () async {
    final first = Completer<bool>();
    final sent = <int>[];
    final emitter = BackpressureStreamEmitter(
      maxQueueSize: 1,
      initialSendCredit: 1,
      emit: (_, payload) async {
        sent.add(payload['chunk_index'] as int);
        return first.isCompleted ? true : first.future;
      },
      onRegister: (_, _) => true,
      onUnregister: (_) {},
    );
    final active = emitter.emitChunk(chunk(0));
    await Future<void>.delayed(Duration.zero);
    expect(emitter.availableCredit, 0);
    final waiting = emitter.emitChunk(chunk(1));
    expect(await emitter.emitChunk(chunk(2)), isFalse);
    expect(emitter.queuedChunks, 1);
    first.complete(true);
    expect(await active, isTrue);
    expect(await waiting, isTrue);
    emitter.releaseChunks(1);
    await Future<void>.delayed(Duration.zero);
    expect(sent, [0, 1]);
    expect(emitter.queuedChunksPeak, 1);
  });

  test('transport loss during wire await cannot emit a later chunk', () async {
    final gate = Completer<bool>();
    var sent = 0;
    final emitter = BackpressureStreamEmitter(
      initialSendCredit: 3,
      emit: (_, _) {
        sent++;
        return gate.future;
      },
      onRegister: (_, _) => true,
      onUnregister: (_) {},
    );
    final active = emitter.emitChunk(chunk(0));
    await Future<void>.delayed(Duration.zero);
    final waiting = emitter.emitChunk(chunk(1));
    emitter.onTransportLoss();
    gate.complete(true);
    expect(await active, isFalse);
    expect(await waiting, isFalse);
    expect(sent, 1);
    expect(emitter.queuedChunks, 0);
  });

  test('complete is emitted once after all accepted chunks', () async {
    final events = <String>[];
    var removed = 0;
    final emitter = BackpressureStreamEmitter(
      initialSendCredit: 0,
      emit: (event, _) async {
        events.add(event);
        return true;
      },
      onRegister: (_, _) => true,
      onUnregister: (_) => removed++,
    );
    await emitter.emitChunk(chunk(0));
    final complete = RpcStreamComplete(streamId: 's', requestId: 'r', totalRows: 1);
    await emitter.emitComplete(complete);
    await emitter.emitComplete(complete);
    emitter.releaseChunks(1);
    await Future<void>.delayed(Duration.zero);
    expect(events, ['rpc:chunk', 'rpc:complete']);
    expect(removed, 1);
    expect(await emitter.emitChunk(chunk(1)), isFalse);
  });
}
