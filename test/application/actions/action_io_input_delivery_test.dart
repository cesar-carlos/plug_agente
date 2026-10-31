import 'dart:async';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/action_io_input_delivery.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_input_pipe.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:plug_agente/infrastructure/stores/drift_action_io_journal.dart';
import 'package:result_dart/result_dart.dart';

final class _Pipe implements IActionIoInputPipe {
  final writes = <List<int>>[];
  int closes = 0;
  Future<Result<Unit>> Function()? onWrite;
  @override
  Future<Result<Unit>> write(Uint8List bytes) async {
    writes.add(bytes.toList());
    return onWrite == null ? const Success(unit) : onWrite!();
  }

  @override
  Future<Result<Unit>> close() async {
    closes++;
    return const Success(unit);
  }
}

void main() {
  late ActionIoJournalDatabase db;
  late DriftActionIoJournal journal;
  late _Pipe pipe;
  var stopped = 0;
  setUp(() async {
    db = ActionIoJournalDatabase(NativeDatabase.memory());
    journal = DriftActionIoJournal(db, ActionIoPayloadCipher(keyId: 'key', key: SecretKey(List.filled(32, 7))));
    pipe = _Pipe();
    stopped = 0;
    (await journal.claim(
      const ActionIoSessionIntent(
        executionId: 'e',
        installationId: 'i',
        agentId: 'a',
        clientId: 'c',
        actionId: 'action',
        idempotencyKey: 'key',
        fingerprint: 'f',
        triggerId: 't',
        definitionHash: 'h',
      ),
    )).getOrThrow();
    (await journal.markStarting('e')).getOrThrow();
    (await journal.markRunning('e')).getOrThrow();
  });
  tearDown(() => db.close());
  Future<void> admit(String id, int seq, List<int> bytes, {bool close = false}) async {
    (await journal.admitInput(
      executionId: 'e',
      clientId: 'c',
      messageId: id,
      sequence: seq,
      bytes: bytes,
      close: close,
    )).getOrThrow();
  }

  ActionIoInputDelivery delivery({Future<Result<Unit>> Function()? authorize}) => ActionIoInputDelivery(
    executionId: 'e',
    journal: journal,
    pipe: pipe,
    authorize: authorize ?? () async => const Success(unit),
    terminate: () async {
      stopped++;
      return const Success(unit);
    },
  );
  DateTime deadline() => DateTime.now().add(const Duration(seconds: 5));

  test('an input commit wakes the worker even when admission precedes its wait', () async {
    final observer = journal.observeChanges('e');
    addTearDown(observer.close);
    await admit('m', 0, [0, 255]);
    await observer.wait(const Duration(minutes: 1)).timeout(const Duration(seconds: 2));
    expect((await journal.inputStatus('e', 'c', 'm')).getOrThrow().state, ActionIoDeliveryState.accepted);
  });

  test('commits writing before native access and delivers empty messages separately from EOF', () async {
    await admit('first', 0, [0, 255, 13, 10]);
    await admit('empty', 1, []);
    await admit('close', 2, [], close: true);
    pipe.onWrite = () async {
      final id = pipe.writes.length == 1 ? 'first' : 'empty';
      expect((await journal.inputStatus('e', 'c', id)).getOrThrow().state, ActionIoDeliveryState.writing);
      return const Success(unit);
    };
    final worker = delivery();
    for (var i = 0; i < 3; i++) {
      expect(
        (await worker.deliverNext(deadline: deadline())).getOrThrow().receipt!.state,
        ActionIoDeliveryState.written,
      );
    }
    expect(pipe.writes, [
      [0, 255, 13, 10],
      <int>[],
    ]);
    expect(pipe.closes, 1);
    expect(stopped, 0);
    expect((await journal.inputStatus('e', 'c', 'close')).getOrThrow().stdinState, ActionIoStdinState.closed);
  });

  test('revocation during journal claim prevents the pending native write', () async {
    await admit('m', 0, [1]);
    var authorizations = 0;
    final denied = ActionAuthorizationFailure('Credential revoked.');
    final worker = delivery(
      authorize: () async {
        authorizations++;
        return authorizations == 1 ? const Success(unit) : Failure(denied);
      },
    );
    expect((await worker.deliverNext(deadline: deadline())).exceptionOrNull(), same(denied));
    expect(pipe.writes, isEmpty);
    expect(stopped, 1);
    final receipt = (await journal.inputStatus('e', 'c', 'm')).getOrThrow();
    expect(receipt.state, ActionIoDeliveryState.failed);
    expect(receipt.confirmedBytes, 0);
  });

  test('persists a partial confirmed prefix and never retries the uncertain message', () async {
    await admit('partial', 0, [0, 255, 13, 10, 26]);
    pipe.onWrite = () async => Failure(ActionIoPipeFailure(confirmedBytes: 3));
    final worker = delivery();
    expect((await worker.deliverNext(deadline: deadline())).isError(), isTrue);
    final receipt = (await journal.inputStatus('e', 'c', 'partial')).getOrThrow();
    expect(receipt.state, ActionIoDeliveryState.unknown);
    expect(receipt.confirmedBytes, 3);
    expect(stopped, 1);
    expect((await worker.deliverNext(deadline: deadline())).isError(), isTrue);
    expect(pipe.writes, hasLength(1));
  });

  for (final close in [false, true]) {
    test('revocation during native write preserves its receipt and blocks queued close=$close', () async {
      await admit('writing', 0, [0, 255]);
      await admit('pending', 1, close ? [] : [26], close: close);
      final entered = Completer<void>();
      final native = Completer<Result<Unit>>();
      var revoked = false;
      final denied = ActionAuthorizationFailure.withContext(
        message: 'Credential revoked.',
        code: 'ACTION_IO_UNAUTHORIZED',
      );
      pipe.onWrite = () {
        entered.complete();
        return native.future;
      };
      final worker = delivery(authorize: () async => revoked ? Failure(denied) : const Success(unit));
      final first = worker.deliverNext(deadline: deadline());
      await entered.future;
      revoked = true;
      final concurrent = await worker.deliverNext(deadline: deadline());
      expect((concurrent.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_DELIVERY_UNAVAILABLE');
      expect((await journal.inputStatus('e', 'c', 'pending')).getOrThrow().state, ActionIoDeliveryState.accepted);
      native.complete(const Success(unit));
      final confirmed = (await first).getOrThrow().receipt!;
      expect(confirmed.state, ActionIoDeliveryState.written);
      expect(confirmed.confirmedBytes, 2);
      expect((await worker.deliverNext(deadline: deadline())).exceptionOrNull(), same(denied));
      final untouched = (await journal.inputStatus('e', 'c', 'pending')).getOrThrow();
      expect(untouched.state, ActionIoDeliveryState.accepted);
      expect(untouched.confirmedBytes, 0);
      expect(pipe.writes, [
        [0, 255],
      ]);
      expect(pipe.closes, 0);
      await worker.waitForNativeCompletion();
    });
  }

  test('late native success cannot overwrite unknown delivery or authorize replay', () async {
    await admit('m', 0, [1]);
    final native = Completer<Result<Unit>>();
    pipe.onWrite = () => native.future;
    final worker = delivery();
    final result = await worker.deliverNext(deadline: DateTime.now().add(const Duration(milliseconds: 100)));
    expect(result.exceptionOrNull(), isA<ActionIoPipeFailure>());
    expect((result.exceptionOrNull()! as ActionIoPipeFailure).code, 'ACTION_STDIN_WRITE_TIMEOUT');
    expect(stopped, 1);
    var settled = false;
    final settlement = worker.waitForNativeCompletion().then((_) {
      settled = true;
    });
    await Future<void>.delayed(Duration.zero);
    expect(settled, isFalse);
    native.complete(const Success(unit));
    await settlement;
    expect((await worker.deliverNext(deadline: deadline())).isError(), isTrue);
    final receipt = (await journal.inputStatus('e', 'c', 'm')).getOrThrow();
    expect(receipt.state, ActionIoDeliveryState.unknown);
    expect(receipt.confirmedBytes, isNull);
    expect((await db.select(db.actionIoMessages).getSingle()).failureCode, 'ACTION_STDIN_WRITE_TIMEOUT');
    expect(pipe.writes, [
      [1],
    ]);
  });
}
