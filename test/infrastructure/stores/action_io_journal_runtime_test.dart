import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/infrastructure/bootstrap/infrastructure_shutdown_port.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_runtime.dart';
import 'package:plug_agente/infrastructure/stores/action_io_secure_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late String path;
  final runtimes = <ActionIoJournalRuntime>[];
  ActionIoJournalRuntime runtime() {
    final result = ActionIoJournalRuntime(path, freeBytes: (_) async => 1 << 30);
    runtimes.add(result);
    return result;
  }

  const intent = ActionIoSessionIntent(
    executionId: 'execution',
    installationId: 'installation',
    agentId: 'agent',
    clientId: 'client',
    actionId: 'action',
    idempotencyKey: 'key',
    fingerprint: 'fingerprint',
    triggerId: 'trigger',
    definitionHash: 'definition',
  );

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('action-io-runtime-test-');
    path = '${directory.path}/journal.sqlite';
  });
  tearDown(() async {
    for (final item in runtimes) {
      (await item.close()).getOrThrow();
    }
    runtimes.clear();
    await directory.delete(recursive: true);
  });

  test('invalid SQLite header refuses startup without replacing evidence or the key', () async {
    final first = runtime();
    (await first.initialize()).getOrThrow();
    (await first.journal.claim(intent)).getOrThrow();
    (await first.close()).getOrThrow();
    final originalKey = await const FlutterSecureStorage().read(key: ActionIoSecureKeyStore.storageKey);
    final file = File(path);
    final damaged = await file.readAsBytes();
    damaged[0] ^= 255;
    await file.writeAsBytes(damaged, flush: true);
    final reopened = runtime();
    final result = await reopened.prepare(enabled: false);
    expect(result.isError(), isTrue);
    expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_FAILED');
    expect(reopened.isReady, isFalse);
    expect(await file.readAsBytes(), damaged);
    expect(await const FlutterSecureStorage().read(key: ActionIoSecureKeyStore.storageKey), originalKey);
    expect((await reopened.ownsExecution('execution')).isError(), isTrue);
    expect((await reopened.listExecutionSnapshots(limit: 10)).isError(), isTrue);
  });

  test('reopened corrupted payload refuses the whole page and preserves deduplication evidence', () async {
    final first = runtime();
    (await first.initialize()).getOrThrow();
    (await first.journal.claim(intent)).getOrThrow();
    (await first.journal.markStarting('execution')).getOrThrow();
    (await first.journal.markRunning('execution')).getOrThrow();
    (await first.output.append('execution', ActionIoStream.stdout, [0, 255])).getOrThrow();
    (await first.output.append('execution', ActionIoStream.stderr, [13, 10, 26])).getOrThrow();
    (await first.output.finish('execution', exitCode: 0, complete: true)).getOrThrow();
    (await first.close()).getOrThrow();
    final key = await const FlutterSecureStorage().read(key: ActionIoSecureKeyStore.storageKey);
    final database = ActionIoJournalDatabase(NativeDatabase(File(path)));
    late Uint8List damaged;
    try {
      final payloads = await database.select(database.actionIoPayloads).get();
      damaged = Uint8List.fromList(payloads.last.ciphertext);
      damaged[0] ^= 255;
      await (database.update(database.actionIoPayloads)..where((row) => row.payloadId.equals(payloads.last.payloadId)))
          .write(ActionIoPayloadsCompanion(ciphertext: Value(damaged)));
    } finally {
      await database.close();
    }
    final reopened = runtime();
    (await reopened.prepare(enabled: false)).getOrThrow();
    final page = await reopened.readLocalOutput(executionId: 'execution', afterSequence: 0, maxBytes: 65536);
    expect(page.isError(), isTrue);
    expect(page.exceptionOrNull(), isA<ActionFailure>());
    expect((await reopened.ownsExecution('execution')).getOrThrow(), isTrue);
    expect((await reopened.journal.markStarting('execution')).isError(), isTrue);
    expect(await const FlutterSecureStorage().read(key: ActionIoSecureKeyStore.storageKey), key);
    (await reopened.close()).getOrThrow();
    final inspection = ActionIoJournalDatabase(NativeDatabase(File(path)));
    try {
      final payloads = await inspection.select(inspection.actionIoPayloads).get();
      expect(payloads, hasLength(2));
      expect(payloads.last.ciphertext, damaged);
      expect(await inspection.select(inspection.actionIoSessions).get(), hasLength(1));
    } finally {
      await inspection.close();
    }
  });

  for (final enabled in [false, true]) {
    test('truncated SQLite file refuses recovery without replacing evidence (enabled=$enabled)', () async {
      final first = runtime();
      (await first.initialize()).getOrThrow();
      (await first.journal.claim(intent)).getOrThrow();
      (await first.journal.markStarting('execution')).getOrThrow();
      (await first.journal.markRunning('execution')).getOrThrow();
      (await first.output.append('execution', ActionIoStream.stdout, List<int>.filled(65536, 255))).getOrThrow();
      (await first.close()).getOrThrow();
      final originalKey = await const FlutterSecureStorage().read(key: ActionIoSecureKeyStore.storageKey);
      final file = File(path);
      final original = await file.readAsBytes();
      expect(original.length, greaterThan(65536));
      final damaged = original.sublist(0, original.length - 4096);
      await file.writeAsBytes(damaged, flush: true);

      final reopened = runtime();
      final result = await reopened.prepare(enabled: enabled);
      expect(result.exceptionOrNull(), isA<ActionFailure>());
      expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_FAILED');
      expect(reopened.isReady, isFalse);
      expect((await reopened.ownsExecution('execution')).isError(), isTrue);
      expect((await reopened.listExecutionSnapshots(limit: 10)).isError(), isTrue);
      (await reopened.close()).getOrThrow();
      expect(await file.readAsBytes(), damaged);
      expect(await const FlutterSecureStorage().read(key: ActionIoSecureKeyStore.storageKey), originalKey);
    });
  }

  test('disabled recovery expires terminal output before serving history and preserves deduplication', () async {
    final first = runtime();
    (await first.initialize()).getOrThrow();
    (await first.journal.claim(intent)).getOrThrow();
    (await first.journal.markStarting('execution')).getOrThrow();
    (await first.journal.markRunning('execution')).getOrThrow();
    (await first.output.append('execution', ActionIoStream.stdout, [0, 255])).getOrThrow();
    (await first.output.finish('execution', exitCode: 0, complete: true)).getOrThrow();
    (await first.close()).getOrThrow();
    final database = ActionIoJournalDatabase(NativeDatabase(File(path)));
    await database
        .update(database.actionIoSessions)
        .write(
          ActionIoSessionsCompanion(outputExpiresAt: Value(DateTime.utc(2020))),
        );
    await database.close();

    final reopened = runtime();
    (await reopened.prepare(enabled: false)).getOrThrow();
    final read = await reopened.readLocalOutput(executionId: 'execution', afterSequence: 0, maxBytes: 65536);
    expect(read.isError(), isTrue);
    expect((read.exceptionOrNull()! as ActionFailure).code, 'OUTPUT_EXPIRED');
    expect((await reopened.journal.claim(intent)).getOrThrow().created, isFalse);
    (await reopened.close()).getOrThrow();
    final inspection = ActionIoJournalDatabase(NativeDatabase(File(path)));
    try {
      final payload = await inspection.select(inspection.actionIoPayloads).getSingle();
      expect(payload.ciphertext, isEmpty);
      expect(payload.plaintextBytes, 0);
    } finally {
      await inspection.close();
    }
  });

  test('routing distinguishes no journal, owned execution and unavailable evidence', () async {
    final first = runtime();
    expect((await first.ownsExecution('execution')).getOrThrow(), isFalse);
    expect(File(path).existsSync(), isFalse);
    (await first.initialize()).getOrThrow();
    expect((await first.ownsExecution('execution')).getOrThrow(), isFalse);
    (await first.journal.claim(intent)).getOrThrow();
    expect((await first.ownsExecution('execution')).getOrThrow(), isTrue);
    (await first.close()).getOrThrow();
    expect((await first.ownsExecution('execution')).isError(), isTrue);
    final unopened = runtime();
    expect((await unopened.ownsExecution('execution')).isError(), isTrue);
  });

  test('periodic retention removes terminal bytes without restarting the runtime', () async {
    var now = DateTime.now();
    final active = ActionIoJournalRuntime(
      path,
      clock: () => now,
      freeBytes: (_) async => 1 << 30,
      retentionInterval: const Duration(milliseconds: 20),
    );
    runtimes.add(active);
    (await active.initialize()).getOrThrow();
    (await active.journal.claim(intent)).getOrThrow();
    (await active.journal.markStarting('execution')).getOrThrow();
    (await active.journal.markRunning('execution')).getOrThrow();
    (await active.output.append('execution', ActionIoStream.stdout, [0, 255])).getOrThrow();
    (await active.output.finish('execution', exitCode: 0, complete: true)).getOrThrow();
    expect((await active.journal.getExecutionSnapshot('execution')).getOrThrow().outputExpired, isFalse);
    now = now.add(const Duration(days: 4));
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (!(await active.journal.getExecutionSnapshot('execution')).getOrThrow().outputExpired &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect((await active.journal.getExecutionSnapshot('execution')).getOrThrow().outputExpired, isTrue);
    (await active.close()).getOrThrow();
    final inspection = ActionIoJournalDatabase(NativeDatabase(File(path)));
    try {
      expect((await inspection.select(inspection.actionIoPayloads).getSingle()).ciphertext, isEmpty);
    } finally {
      await inspection.close();
    }
  });

  test('local history distinguishes empty disabled installation from unavailable journal', () async {
    final first = runtime();
    expect((await first.listExecutionSnapshots(limit: 10)).getOrThrow(), isEmpty);
    expect(await directory.list().toList(), isEmpty);
    expect((await first.listExecutionSnapshots(limit: 0)).isError(), isTrue);
    (await first.initialize()).getOrThrow();
    (await first.journal.claim(intent)).getOrThrow();
    final entries = (await first.listExecutionSnapshots(limit: 10, actionId: 'action')).getOrThrow();
    expect(entries.single.session.executionId, 'execution');
    expect(entries.single.processState, 'queued');
    (await first.close()).getOrThrow();
    expect((await first.listExecutionSnapshots(limit: 10)).isError(), isTrue);
    final unopened = runtime();
    expect((await unopened.listExecutionSnapshots(limit: 10)).isError(), isTrue);
    (await unopened.prepare(enabled: false)).getOrThrow();
    final recovered = (await unopened.listExecutionSnapshots(limit: 10)).getOrThrow();
    expect(recovered.single.session.executionId, 'execution');
    expect(recovered.single.processState, 'unknown');
  });

  test('local output reads bounded original bytes without changing execution or input', () async {
    final first = runtime();
    expect(
      (await first.readLocalOutput(executionId: 'execution', afterSequence: 0, maxBytes: 65536)).isError(),
      isTrue,
    );
    (await first.initialize()).getOrThrow();
    (await first.journal.claim(intent)).getOrThrow();
    (await first.journal.markStarting('execution')).getOrThrow();
    (await first.journal.markRunning('execution')).getOrThrow();
    const bytes = [0, 13, 10, 26, 255, 128];
    (await first.output.append('execution', ActionIoStream.stdout, bytes)).getOrThrow();
    (await first.output.append('execution', ActionIoStream.stderr, [7])).getOrThrow();
    final page = (await first.readLocalOutput(
      executionId: 'execution',
      afterSequence: 0,
      maxBytes: 65536,
    )).getOrThrow();
    expect((page.events.first as ActionIoOutputEvent).bytes, bytes);
    expect((page.events.last as ActionIoOutputEvent).stream, ActionIoStream.stderr);
    expect(page.nextSequence, 2);
    final after = (await first.journal.getExecutionSnapshot('execution')).getOrThrow();
    expect(after.processState, 'running');
    expect(after.nextInputSequence, 0);
    expect((await first.readLocalOutput(executionId: 'execution', afterSequence: 0, maxBytes: 1)).isError(), isTrue);
    (await first.close()).getOrThrow();
    expect(
      (await first.readLocalOutput(executionId: 'execution', afterSequence: 0, maxBytes: 65536)).isError(),
      isTrue,
    );
  });

  test('exclusive owner prevents recovery by a second live runtime', () async {
    final first = runtime();
    (await first.initialize()).getOrThrow();
    (await first.journal.claim(intent)).getOrThrow();
    final second = runtime();
    expect((await second.initialize()).isError(), isTrue);
    expect(second.isReady, isFalse);
    // A failed competing open must not relabel the live execution.
    expect((await first.journal.markStarting('execution')).isSuccess(), isTrue);
    (await first.close()).getOrThrow();
    final reopened = runtime();
    (await reopened.initialize()).getOrThrow();
    expect((await reopened.journal.claim(intent)).getOrThrow().created, isFalse);
  });

  test('disabled preparation creates nothing but still recovers an existing journal', () async {
    final disabled = runtime();
    (await disabled.prepare(enabled: false)).getOrThrow();
    expect(disabled.isReady, isFalse);
    expect(await directory.list().toList(), isEmpty);
    expect(await const FlutterSecureStorage().read(key: ActionIoSecureKeyStore.storageKey), isNull);
    (await disabled.prepare(enabled: true)).getOrThrow();
    (await disabled.journal.claim(intent)).getOrThrow();
    (await disabled.close()).getOrThrow();
    final reopened = runtime();
    (await reopened.prepare(enabled: false)).getOrThrow();
    expect(reopened.isReady, isTrue);
    expect((await reopened.journal.claim(intent)).getOrThrow().created, isFalse);
    expect((await reopened.journal.markStarting('execution')).isError(), isTrue);
  });

  test('restart retains uncertain delivery without replay and refuses missing key', () async {
    final first = runtime();
    (await first.initialize()).getOrThrow();
    (await first.journal.claim(intent)).getOrThrow();
    (await first.journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'input',
      sequence: 0,
      bytes: [0, 255],
    )).getOrThrow();
    (await first.journal.markStarting('execution')).getOrThrow();
    (await first.journal.markRunning('execution')).getOrThrow();
    (await first.journal.beginNextInput('execution')).getOrThrow();
    (await first.close()).getOrThrow();
    final reopened = runtime();
    (await reopened.initialize()).getOrThrow();
    final receipt = (await reopened.journal.inputStatus('execution', 'client', 'input')).getOrThrow();
    expect(receipt.state, ActionIoDeliveryState.unknown);
    expect(receipt.confirmedBytes, isNull);
    (await reopened.close()).getOrThrow();
    await const FlutterSecureStorage().delete(key: ActionIoSecureKeyStore.storageKey);
    final missing = runtime();
    expect((await missing.initialize()).isError(), isTrue);
    expect(missing.isReady, isFalse);
    expect(await const FlutterSecureStorage().read(key: ActionIoSecureKeyStore.storageKey), isNull);
  });

  test('close during initialization never publishes journals and is idempotent', () async {
    final current = runtime();
    final opening = current.initialize();
    final closing = current.close();
    expect((await opening).isError(), isTrue);
    (await closing).getOrThrow();
    expect(current.isReady, isFalse);
    expect(() => current.journal, throwsStateError);
    expect((await current.initialize()).isError(), isTrue);
    (await current.close()).getOrThrow();
  });

  test('infrastructure shutdown closes the prepared journal and releases ownership', () async {
    final current = runtime();
    (await current.prepare(enabled: true)).getOrThrow();
    final dependencies = GetIt.asNewInstance();
    dependencies.registerSingleton<ActionIoJournalRuntime>(current);
    await InfrastructureShutdownPort(dependencies).closeLocalDatabase();
    expect(current.isReady, isFalse);
    final reopened = runtime();
    (await reopened.initialize()).getOrThrow();
    expect(reopened.isReady, isTrue);
    await dependencies.reset();
  });

  test('mismatched key refuses recovery and original key can reopen retained data', () async {
    final current = runtime();
    (await current.initialize()).getOrThrow();
    (await current.journal.claim(intent)).getOrThrow();
    (await current.journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'input',
      sequence: 0,
      bytes: [0, 255],
    )).getOrThrow();
    (await current.close()).getOrThrow();
    const storage = FlutterSecureStorage();
    final original = (await storage.read(key: ActionIoSecureKeyStore.storageKey))!;
    final replacement = jsonDecode(original) as Map<String, dynamic>;
    replacement['key_id'] = 'unrelated-key';
    await storage.write(key: ActionIoSecureKeyStore.storageKey, value: jsonEncode(replacement));
    final rejected = runtime();
    expect((await rejected.initialize()).isError(), isTrue);
    expect(rejected.isReady, isFalse);
    await storage.write(key: ActionIoSecureKeyStore.storageKey, value: original);
    final restored = runtime();
    (await restored.initialize()).getOrThrow();
    final receipt = (await restored.journal.inputStatus('execution', 'client', 'input')).getOrThrow();
    expect(receipt.state, ActionIoDeliveryState.failed);
    expect(receipt.confirmedBytes, 0);
  });
}
