import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart' hide ActionIoEvent;
import 'package:plug_agente/infrastructure/stores/action_io_journal_runtime.dart';
import 'package:plug_agente/infrastructure/stores/action_io_secure_key_store.dart';

/// Called only after native workers and the previous runtime have closed.
Future<void> verifyActionIoRuntimeRecovery(
  String path,
  String keyName,
  String executionId,
  List<int> expectedBytes,
) async {
  if (!keyName.startsWith('fixture_action_io_') || keyName == ActionIoSecureKeyStore.storageKey) {
    throw StateError('Only an explicitly namespaced test key may be fault-injected.');
  }
  ActionIoJournalRuntime open() => ActionIoJournalRuntime(
    path,
    keyStore: ActionIoSecureKeyStore(lockPath: '$path.key.lock', keyName: keyName),
  );
  Future<void> reopenAndCompare() async {
    final runtime = open();
    try {
      (await runtime.prepare(enabled: false)).getOrThrow();
      final snapshot = (await runtime.journal.getExecutionSnapshot(executionId)).getOrThrow();
      expect(snapshot.processState, 'finished');
      final page = (await runtime.readLocalOutput(
        executionId: executionId,
        afterSequence: 0,
        maxBytes: ActionIoLimits.pageBytes,
      )).getOrThrow();
      expect(page.outputComplete, isTrue);
      for (final stream in ActionIoStream.values) {
        expect(
          page.events
              .whereType<ActionIoOutputEvent>()
              .where((event) => event.stream == stream)
              .expand((event) => event.bytes)
              .toList(),
          expectedBytes,
        );
      }
    } finally {
      (await runtime.close()).getOrThrow();
    }
  }

  await reopenAndCompare();
  final inspection = ActionIoJournalDatabase(NativeDatabase(File(path)));
  final event =
      await (inspection.select(inspection.actionIoEvents)
            ..where((row) => row.executionId.equals(executionId))
            ..where((row) => row.stream.equals('stdout'))
            ..limit(1))
          .getSingle();
  final payload = await (inspection.select(
    inspection.actionIoPayloads,
  )..where((row) => row.payloadId.equals(event.payloadId!))).getSingle();
  final changed = Uint8List.fromList(payload.ciphertext);
  changed[0] ^= 1;
  await (inspection.update(inspection.actionIoPayloads)..where((row) => row.payloadId.equals(payload.payloadId))).write(
    ActionIoPayloadsCompanion(ciphertext: Value(changed)),
  );
  await inspection.close();
  final corrupt = open();
  try {
    (await corrupt.prepare(enabled: false)).getOrThrow();
    final refused = await corrupt.readLocalOutput(
      executionId: executionId,
      afterSequence: 0,
      maxBytes: ActionIoLimits.pageBytes,
    );
    expect(refused.isError(), isTrue);
    expect(refused.exceptionOrNull(), isA<ActionFailure>());
    expect((refused.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_INTEGRITY_FAILED');
  } finally {
    (await corrupt.close()).getOrThrow();
    final restore = ActionIoJournalDatabase(NativeDatabase(File(path)));
    try {
      await (restore.update(restore.actionIoPayloads)..where((row) => row.payloadId.equals(payload.payloadId))).write(
        ActionIoPayloadsCompanion(ciphertext: Value(payload.ciphertext)),
      );
    } finally {
      await restore.close();
    }
  }
  await reopenAndCompare();
  const storage = FlutterSecureStorage();
  final original = await storage.read(key: keyName);
  expect(original, isNotNull);
  await storage.delete(key: keyName);
  final unavailable = open();
  try {
    final result = await unavailable.prepare(enabled: false);
    expect(result.isError(), isTrue);
    expect((result.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_KEY_UNAVAILABLE');
    expect(unavailable.isReady, isFalse);
    expect(await storage.read(key: keyName), isNull);
  } finally {
    (await unavailable.close()).getOrThrow();
    await storage.write(key: keyName, value: original);
  }
  await reopenAndCompare();
}
