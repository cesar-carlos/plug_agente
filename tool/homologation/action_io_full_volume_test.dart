import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart' hide ActionIoEvent;
import 'package:plug_agente/infrastructure/stores/action_io_output_journal.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:plug_agente/infrastructure/stores/action_io_physical_budget.dart';
import 'package:plug_agente/infrastructure/stores/drift_action_io_journal.dart';
import 'package:win32/win32.dart' as win32;

// Run only through action_io_full_volume.ps1, which owns the disposable VHD.
void main() {
  test('physical volume exhaustion refuses growth and preserves durable bytes after reopen', () async {
    final root = Platform.environment['ACTION_IO_FULL_VOLUME_ROOT'];
    final identity = Platform.environment['ACTION_IO_FULL_VOLUME_ID'];
    if (!Platform.isWindows || root == null || identity == null) {
      fail('Use action_io_full_volume.ps1 with its verified private VHD. Missing setup is not acceptance.');
    }
    expect(RegExp(r'^[a-f0-9]{32}$').hasMatch(identity), isTrue);
    expect(p.basename(root), 'fixture-$identity');
    expect(p.rootPrefix(root).toUpperCase(), isNot(anyOf(r'C:\', r'D:\')));
    expect(await File(p.join(root, 'identity')).readAsString(), identity);
    expect(await Directory(root).resolveSymbolicLinks(), p.normalize(root));
    final name = root.toPcwstr();
    final available = calloc<Uint64>();
    final total = calloc<Uint64>();
    final free = calloc<Uint64>();
    try {
      expect(win32.GetDiskFreeSpaceEx(name, available, total, free).value, isTrue);
      expect(total.value, inInclusiveRange(32 * 1024 * 1024, 128 * 1024 * 1024));
    } finally {
      calloc.free(name);
      calloc.free(available);
      calloc.free(total);
      calloc.free(free);
    }
    final file = File(p.join(root, 'journal.sqlite'));
    expect(file.existsSync(), isFalse);
    var db = ActionIoJournalDatabase(NativeDatabase(file));
    final cipher = ActionIoPayloadCipher(keyId: 'fixture', key: SecretKey(List.filled(32, 1)));
    final filler = File(p.join(root, 'bounded-filler'));
    try {
      await db
          .into(db.actionIoSessions)
          .insert(
            ActionIoSessionsCompanion.insert(
              executionId: 'execution',
              installationId: 'installation',
              agentId: 'agent',
              clientId: 'client',
              actionId: 'action',
              idempotencyKey: 'key',
              fingerprint: 'fingerprint',
              triggerId: 'trigger',
              definitionHash: 'definition',
              processState: 'running',
              stdinState: 'open',
              captureState: 'capturing',
              createdAt: DateTime.now(),
            ),
          );
      var output = ActionIoOutputJournal(db, cipher);
      (await output.append('execution', ActionIoStream.stdout, [0, 255, 26])).getOrThrow();
      final handle = await filler.open(mode: FileMode.writeOnly);
      var exhausted = false;
      try {
        final block = Uint8List(4096)..fillRange(0, 4096, 65);
        for (var bytes = 0; bytes <= 128 * 1024 * 1024; bytes += block.length) {
          await handle.writeFrom(block);
        }
      } on FileSystemException catch (error) {
        expect(error.osError?.errorCode, anyOf(39, 112));
        exhausted = true;
      } finally {
        await handle.close();
      }
      expect(exhausted, isTrue, reason: 'Must observe an actual native disk-full error.');
      final refused = await ActionIoPhysicalBudget(file.path).checkAdmission(65536);
      expect((refused.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_SPACE_EXHAUSTED');
      // Bypass only the advisory capacity callback to exercise the real SQLite
      // race where another writer consumes space after admission.
      final failed = await output.append('execution', ActionIoStream.stdout, List.filled(65536, 65));
      expect((failed.exceptionOrNull()! as ActionFailure).code, 'ACTION_IO_STORAGE_FAILED');
      await filler.delete();
      await db.close();
      db = ActionIoJournalDatabase(NativeDatabase(file));
      final journal = DriftActionIoJournal(db, cipher);
      expect((await journal.reconcileInterrupted()).getOrThrow(), 1);
      output = ActionIoOutputJournal(db, cipher);
      final retained = (await output.read(
        executionId: 'execution',
        clientId: 'client',
        afterSequence: 0,
        maxBytes: 65536,
      )).getOrThrow();
      expect(retained.events.whereType<ActionIoOutputEvent>().expand((event) => event.bytes), [0, 255, 26]);
      expect(retained.outputComplete, isFalse);
      expect((await journal.getExecutionSnapshot('execution')).getOrThrow().processState, 'unknown');
      expect((await journal.markStarting('execution')).isError(), isTrue);
      expect(await db.select(db.actionIoPayloads).get(), hasLength(1));
      expect((await db.customSelect('PRAGMA integrity_check').getSingle()).read<String>('integrity_check'), 'ok');
    } finally {
      await db.close();
    }
  });
}
