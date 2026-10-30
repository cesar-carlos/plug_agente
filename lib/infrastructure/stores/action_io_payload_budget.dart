import 'package:drift/drift.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart';

/// Checks content capacity inside the same transaction that inserts the payload.
Future<int> readActionIoPayloadBytes(ActionIoJournalDatabase db) async {
  final total = db.actionIoPayloads.plaintextBytes.sum();
  final minimum = db.actionIoPayloads.plaintextBytes.min();
  final row = await (db.selectOnly(db.actionIoPayloads)..addColumns([total, minimum])).getSingle();
  if ((row.read(minimum) ?? 0) < 0) {
    throw ActionRuntimeFailure.withContext(
      message: 'The I/O content storage accounting is invalid.',
      code: 'ACTION_IO_STORAGE_BUDGET_INVALID',
      context: {'retryable': false},
    );
  }
  return row.read(total) ?? 0;
}

Future<void> requireActionIoPayloadCapacity(ActionIoJournalDatabase db, int additionalBytes) async {
  final used = await readActionIoPayloadBytes(db);
  if (used < 0 || additionalBytes < 0 || used + additionalBytes > ActionIoLimits.payloadBytes) {
    throw ActionRuntimeFailure.withContext(
      message: 'The I/O content storage limit has been reached.',
      code: 'ACTION_IO_STORAGE_QUOTA_EXCEEDED',
      context: {'retryable': false},
    );
  }
}
