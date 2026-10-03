import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/infrastructure/codecs/transport_work_pool.dart';

void holdWorker(SendPort ready) {
  final input = ReceivePort();
  ready.send(input.sendPort);
  input.listen((dynamic _) {});
}

void exitingWorker(SendPort ready) {
  ready.send(ReceivePort().sendPort);
  Isolate.exit();
}

void observingWorker(List<SendPort> ports) {
  final input = ReceivePort();
  ports[0].send(input.sendPort);
  input.listen((dynamic message) => ports[1].send((message as List).first));
}

Future<void> waitForActive(TransportWorkPool pool) async {
  for (var turn = 0; turn < 1000 && pool.activeJobs == 0; turn++) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
  expect(pool.activeJobs, 1);
}

void main() {
  group('TransportWorkPool lifecycle', () {
    test('a late reply after dispose cannot complete cancelled work again', () async {
      final observed = ReceivePort();
      final replyFuture = observed.first;
      final pool = TransportWorkPool(
        workerCount: 1,
        spawnWorker: (ready, errors, exit) =>
            Isolate.spawn(observingWorker, [ready, observed.sendPort], onError: errors, onExit: exit),
      );
      final pending = pool
          .submit<Object>(TransportWorkOperation.jsonEncode, {})
          .then((_) => false, onError: (Object _) => true);
      final reply = await replyFuture as SendPort;
      await pool.dispose();
      expect(await pending, isTrue);
      reply.send([true, 'late']);
      await Future<void>.delayed(Duration.zero);
      expect(pool.completedJobs, 0);
      expect(pool.cancelledJobs, 1);
      expect(pool.openReplyPorts, 0);
      observed.close();
    });
    test('completes work and keeps one bounded worker set', () async {
      final pool = TransportWorkPool(workerCount: 2);
      addTearDown(pool.dispose);
      final jobs = List.generate(50, (i) => pool.submit<Uint8List>(TransportWorkOperation.jsonEncode, {'i': i}));
      expect(await Future.wait(jobs), hasLength(50));
      expect(pool.liveWorkers, 2);
      expect(pool.activeJobs, 0);
      expect(pool.queuedJobs, 0);
      expect(pool.completedJobs, 50);
    });

    test('dispose settles active and queued jobs and closes their ports', () async {
      final pool = TransportWorkPool(
        workerCount: 1,
        spawnWorker: (ready, errors, exit) => Isolate.spawn(holdWorker, ready, onError: errors, onExit: exit),
      );
      final pending = List.generate(
        10,
        (_) => pool
            .submit<Uint8List>(TransportWorkOperation.jsonEncode, {'i': 1})
            .then((_) => false, onError: (Object _) => true),
      );
      await waitForActive(pool);
      await pool.dispose();
      expect(await Future.wait(pending), everyElement(isTrue));
      expect(pool.cancelledJobs, 10);
      expect(pool.completedJobs, 0);
      expect(pool.openReplyPorts, 0);
      expect(pool.liveWorkers, 0);
      expect(pool.queuedJobs, 0);
      await pool.dispose();
      await expectLater(pool.submit<Object>(TransportWorkOperation.jsonEncode, {}), throwsStateError);
    });

    test('dispose during startup kills a worker that arrives afterwards', () async {
      final gate = Completer<void>();
      final pool = TransportWorkPool(
        workerCount: 1,
        spawnWorker: (ready, errors, exit) async {
          await gate.future;
          return Isolate.spawn(holdWorker, ready, onError: errors, onExit: exit);
        },
      );
      final result = pool
          .submit<Uint8List>(TransportWorkOperation.jsonEncode, {})
          .then((_) => false, onError: (Object _) => true);
      final stopped = pool.dispose();
      expect(await result, isTrue);
      gate.complete();
      await stopped;
      expect(pool.liveWorkers, 0);
      expect(pool.openReplyPorts, 0);
    });

    test('startup failure settles queued work and rejects new work', () async {
      final pool = TransportWorkPool(spawnWorker: (_, _, _) async => throw StateError('spawn failed'));
      addTearDown(pool.dispose);
      await expectLater(pool.submit<Object>(TransportWorkOperation.jsonEncode, {}), throwsStateError);
      await expectLater(pool.submit<Object>(TransportWorkOperation.jsonEncode, {}), throwsStateError);
      expect(pool.failedJobs, 1);
      expect(pool.queuedJobs, 0);
    });

    test('unexpected worker exit cannot leave a job pending', () async {
      final pool = TransportWorkPool(
        workerCount: 1,
        spawnWorker: (ready, errors, exit) => Isolate.spawn(exitingWorker, ready, onError: errors, onExit: exit),
      );
      addTearDown(pool.dispose);
      await expectLater(
        pool.submit<Object>(TransportWorkOperation.jsonEncode, {}).timeout(const Duration(seconds: 2)),
        throwsStateError,
      );
      expect(pool.failedJobs, 1);
      expect(pool.activeJobs, 0);
      expect(pool.queuedJobs, 0);
    });
  });
}
