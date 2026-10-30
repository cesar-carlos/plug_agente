import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart';
import 'package:plug_agente/infrastructure/stores/action_io_output_journal.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:plug_agente/infrastructure/stores/drift_action_io_journal.dart';

const crashIntent = ActionIoSessionIntent(
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

ActionIoPayloadCipher crashCipher() =>
    ActionIoPayloadCipher(keyId: 'isolated-test', key: SecretKey(List.filled(32, 7)));

// Test-only process: exit without closing Drift before or after a commit.
Future<void> main(List<String> args) async {
  final db = ActionIoJournalDatabase(NativeDatabase(File(args[0])));
  final journal = DriftActionIoJournal(db, crashCipher());
  Future<void> boundary(String stage, Future<Object?> Function() operation) async {
    if (args[1] == '$stage-uncommitted') {
      await db.transaction(() async {
        await operation();
        exit(77);
      });
    }
    await operation();
    if (args[1] == stage) exit(77);
  }

  await boundary('claimed', () async => (await journal.claim(crashIntent)).getOrThrow());
  await boundary(
    'admitted',
    () async => (await journal.admitInput(
      executionId: 'execution',
      clientId: 'client',
      messageId: 'input',
      sequence: 0,
      bytes: [0, 13, 10, 26, 255],
    )).getOrThrow(),
  );
  await boundary('starting', () async => (await journal.markStarting('execution')).getOrThrow());
  await boundary('running', () async => (await journal.markRunning('execution')).getOrThrow());
  await boundary('writing', () async => (await journal.beginNextInput('execution')).getOrThrow());
  await boundary(
    'written',
    () async => (await journal.finishInput(
      'execution',
      'input',
      ActionIoDeliveryState.written,
      confirmedBytes: 5,
    )).getOrThrow(),
  );
  final output = ActionIoOutputJournal(db, crashCipher());
  await boundary(
    'stdout',
    () async => (await output.append('execution', ActionIoStream.stdout, [0, 255, 26])).getOrThrow(),
  );
  await boundary(
    'stderr',
    () async => (await output.append('execution', ActionIoStream.stderr, [13, 10, 128])).getOrThrow(),
  );
  await boundary('completed', () async => (await output.finish('execution', exitCode: 0, complete: true)).getOrThrow());
  throw StateError('Unknown interruption boundary');
}
