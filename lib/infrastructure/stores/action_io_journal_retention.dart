import 'package:drift/drift.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart';
import 'package:result_dart/result_dart.dart';

/// Removes expired content while retaining receipts, identities and nonce history.
final class ActionIoJournalRetention {
  ActionIoJournalRetention(this._db);

  final ActionIoJournalDatabase _db;

  Future<Result<int>> expire(DateTime now) async {
    try {
      final count = await _db.transaction(() async {
        final sessions = await (_db.select(
          _db.actionIoSessions,
        )..where((s) => s.processState.equals('finished') & s.terminalAt.isNotNull())).get();
        var expired = 0;
        for (final session in sessions) {
          final outputDeadline = session.outputExpiresAt;
          if (!session.outputExpired && outputDeadline != null && !now.isBefore(outputDeadline)) {
            final events = await (_db.select(
              _db.actionIoEvents,
            )..where((e) => e.executionId.equals(session.executionId) & e.eventType.equals('output'))).get();
            for (final event in events) {
              if (event.payloadId != null) await _erase(event.payloadId!);
            }
            await (_db.update(_db.actionIoSessions)..where((s) => s.executionId.equals(session.executionId))).write(
              const ActionIoSessionsCompanion(outputExpired: Value(true)),
            );
            expired++;
          }
          final inputDeadline = session.dedupeExpiresAt;
          if (inputDeadline != null && !now.isBefore(inputDeadline)) {
            final messages = await (_db.select(
              _db.actionIoMessages,
            )..where((m) => m.executionId.equals(session.executionId))).get();
            for (final message in messages) {
              if (message.payloadId != null) await _erase(message.payloadId!);
            }
          }
        }
        return expired;
      });
      return Success(count);
    } on Exception catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'Expired I/O content could not be removed. The journal has been preserved.',
          code: 'ACTION_IO_STORAGE_FAILED',
          context: {'retryable': false, 'cause_type': error.runtimeType.toString()},
        ),
      );
    }
  }

  Future<void> _erase(String payloadId) async {
    // Keep the key/nonce pair reserved even after removing encrypted content.
    await (_db.update(_db.actionIoPayloads)..where((p) => p.payloadId.equals(payloadId))).write(
      ActionIoPayloadsCompanion(
        ciphertext: Value(Uint8List(0)),
        authenticationTag: Value(Uint8List(0)),
        plaintextBytes: const Value(0),
      ),
    );
  }
}
