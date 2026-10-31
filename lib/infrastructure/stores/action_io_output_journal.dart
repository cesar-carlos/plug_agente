import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_journal_changes.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/repositories/i_action_io_metrics.dart';
import 'package:plug_agente/domain/repositories/i_action_io_output_journal.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart' hide ActionIoEvent;
import 'package:plug_agente/infrastructure/stores/action_io_payload_budget.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

final class ActionIoOutputJournal with ActionIoJournalChanges implements IActionIoOutputJournal {
  ActionIoOutputJournal(
    this._db,
    this._cipher, {
    Future<Result<Unit>> Function(int)? physicalCapacity,
    IActionIoMetrics? metrics,
  }) : _physicalCapacity = physicalCapacity,
       _metrics = metrics;
  final IActionIoMetrics? _metrics;
  final Future<Result<Unit>> Function(int)? _physicalCapacity;
  final ActionIoJournalDatabase _db;
  final ActionIoPayloadCipher _cipher;

  @override
  Future<Result<ActionIoOutputEvent>> append(String executionId, ActionIoStream stream, List<int> bytes) async {
    if (bytes.isEmpty ||
        bytes.length > ActionIoLimits.blockBytes ||
        (bytes is! Uint8List && bytes.any((byte) => byte < 0 || byte > 255))) {
      return Failure(_failure('ACTION_IO_INVALID_INPUT'));
    }
    final owned = Uint8List.fromList(bytes);
    final result = await _guard(
      () => _db.transaction(() async {
        final session = await _session(executionId);
        if (!const {'capturing', 'draining'}.contains(session.captureState) || session.outputExpired) {
          throw _failure('ACTION_IO_CAPTURE_CLOSED');
        }
        final remaining =
            ActionIoLimits.executionBytes - session.admittedInputBytes - session.stdoutBytes - session.stderrBytes;
        if (remaining <= 0 ||
            session.nextEventSequence > ActionIoLimits.executionEvents - ActionIoLimits.terminalEventReserve) {
          throw _failure('ACTION_OUTPUT_LIMIT_EXCEEDED');
        }
        final prefix = remaining < owned.length ? Uint8List.sublistView(owned, 0, remaining) : owned;
        (await _physicalCapacity?.call(prefix.length))?.getOrThrow();
        await requireActionIoPayloadCapacity(_db, prefix.length);
        final offset = stream == ActionIoStream.stdout ? session.stdoutBytes : session.stderrBytes;
        final sequence = session.nextEventSequence;
        final aad = ActionIoPayloadCipher.context(
          executionId: executionId,
          channel: stream.name,
          messageId: '',
          sequence: sequence,
          offset: offset,
        );
        final encrypted = await _cipher.encrypt(prefix, context: aad);
        if (encrypted.isError()) throw encrypted.exceptionOrNull()!;
        final payload = encrypted.getOrThrow();
        final id = const Uuid().v4();
        await _db
            .into(_db.actionIoPayloads)
            .insert(
              ActionIoPayloadsCompanion.insert(
                payloadId: id,
                executionId: executionId,
                keyId: payload.keyId,
                nonce: payload.nonce,
                ciphertext: payload.ciphertext,
                authenticationTag: payload.tag,
                authenticatedContext: payload.context,
                plaintextBytes: prefix.length,
              ),
            );
        await _db
            .into(_db.actionIoEvents)
            .insert(
              ActionIoEventsCompanion.insert(
                executionId: executionId,
                sequence: sequence,
                eventType: 'output',
                stream: Value(stream.name),
                byteOffset: Value(offset),
                payloadId: Value(id),
                createdAt: DateTime.now(),
              ),
            );
        await (_db.update(_db.actionIoSessions)..where((s) => s.executionId.equals(executionId))).write(
          ActionIoSessionsCompanion(
            nextEventSequence: Value(sequence + 1),
            stdoutBytes: Value(session.stdoutBytes + (stream == ActionIoStream.stdout ? prefix.length : 0)),
            stderrBytes: Value(session.stderrBytes + (stream == ActionIoStream.stderr ? prefix.length : 0)),
          ),
        );
        return ActionIoOutputEvent(sequence: sequence, stream: stream, offset: offset, bytes: prefix);
      }),
    );
    if (result.isSuccess()) {
      signalJournalCommit(executionId);
      final persisted = result.getOrThrow().bytes.length;
      _metrics?.recordPersistedOutputBytes(persisted);
      // Signal the capture worker only after the permitted prefix is durable.
      if (persisted < owned.length) return Failure(_failure('ACTION_OUTPUT_LIMIT_EXCEEDED'));
    }
    return result;
  }

  @override
  Future<Result<ActionIoReadPage>> read({
    required String executionId,
    required String clientId,
    required int afterSequence,
    required int maxBytes,
  }) => _guard(
    () => _db.transaction(() async {
      if (afterSequence < 0 || maxBytes < ActionIoLimits.blockBytes || maxBytes > ActionIoLimits.pageBytes) {
        throw _failure('ACTION_IO_CURSOR_INVALID');
      }
      final session = await _session(executionId);
      if (session.clientId != clientId) throw _failure('ACTION_IO_UNAUTHORIZED');
      final outputDeadline = session.outputExpiresAt;
      if (session.outputExpired ||
          (session.processState == 'finished' &&
              session.terminalAt != null &&
              outputDeadline != null &&
              !DateTime.now().isBefore(outputDeadline))) {
        throw _failure('OUTPUT_EXPIRED');
      }
      if (afterSequence >= session.nextEventSequence) throw _failure('ACTION_IO_CURSOR_INVALID');
      final rows =
          await (_db.select(_db.actionIoEvents)
                ..where((e) => e.executionId.equals(executionId) & e.sequence.isBiggerThanValue(afterSequence))
                ..orderBy([(e) => OrderingTerm.asc(e.sequence)])
                ..limit(ActionIoLimits.pageEvents))
              .get();
      final events = <ActionIoEvent>[];
      var size = 0;
      // Reserve room for the RPC envelope and terminal metadata.
      var jsonSize = 4096;
      var cursor = afterSequence;
      for (final row in rows) {
        if (row.sequence != cursor + 1) throw _failure('ACTION_IO_INTEGRITY_FAILED');
        if (row.eventType == 'process_exited' || row.eventType == 'completed') {
          if (row.eventType == 'completed' && row.outputComplete == null) throw _failure('ACTION_IO_INTEGRITY_FAILED');
          events.add(
            row.eventType == 'process_exited'
                ? ActionIoProcessExitedEvent(row.sequence, row.exitCode)
                : ActionIoCompletedEvent(
                    row.sequence,
                    outputComplete: row.outputComplete!,
                    failureCode: row.failureCode,
                  ),
          );
          jsonSize += 1024;
          cursor = row.sequence;
          continue;
        }
        if (row.eventType != 'output') throw _failure('ACTION_IO_INTEGRITY_FAILED');
        if (row.sequence != cursor + 1 || row.stream == null || row.byteOffset == null) {
          throw _failure('ACTION_IO_INTEGRITY_FAILED');
        }
        final payload = await (_db.select(
          _db.actionIoPayloads,
        )..where((p) => p.payloadId.equals(row.payloadId ?? ''))).getSingleOrNull();
        if (payload == null || payload.plaintextBytes > ActionIoLimits.blockBytes || payload.plaintextBytes < 1) {
          throw _failure('ACTION_IO_INTEGRITY_FAILED');
        }
        if (size + payload.plaintextBytes > maxBytes) break;
        final stream = switch (row.stream) {
          'stdout' => ActionIoStream.stdout,
          'stderr' => ActionIoStream.stderr,
          _ => throw _failure('ACTION_IO_INTEGRITY_FAILED'),
        };
        // These metadata fields and canonical base64 are ASCII. Count the encoded payload
        // without creating a second base64 string or decrypting a block outside the page.
        final eventSize =
            jsonEncode({
              'sequence': row.sequence,
              'type': 'output',
              'stream': stream.name,
              'offset': row.byteOffset,
              'data_base64': '',
            }).length +
            4 * ((payload.plaintextBytes + 2) ~/ 3) +
            1;
        if (jsonSize + eventSize > ActionIoLimits.jsonBytes) break;
        final aad = ActionIoPayloadCipher.context(
          executionId: executionId,
          channel: stream.name,
          messageId: '',
          sequence: row.sequence,
          offset: row.byteOffset!,
        );
        final decrypted = await _cipher.decrypt(
          ActionIoEncryptedPayload(
            keyId: payload.keyId,
            nonce: payload.nonce,
            ciphertext: payload.ciphertext,
            tag: payload.authenticationTag,
            context: payload.authenticatedContext,
          ),
          expectedContext: aad,
        );
        if (decrypted.isError()) throw decrypted.exceptionOrNull()!;
        final bytes = decrypted.getOrThrow();
        if (bytes.length != payload.plaintextBytes) throw _failure('ACTION_IO_INTEGRITY_FAILED');
        events.add(ActionIoOutputEvent(sequence: row.sequence, stream: stream, offset: row.byteOffset!, bytes: bytes));
        size += bytes.length;
        jsonSize += eventSize;
        cursor = row.sequence;
      }
      if (rows.isNotEmpty && events.isEmpty) throw _failure('ACTION_IO_PAGE_UNTRANSPORTABLE');
      return ActionIoReadPage(
        events: events,
        nextSequence: cursor,
        terminal: session.terminalAt != null,
        outputComplete: session.captureState == 'complete',
      );
    }),
  );

  @override
  Future<Result<bool>> cancelQueued(String executionId, String clientId) async {
    final result = await _guard(
      () => _db.transaction(() async {
        final session = await _session(executionId);
        if (session.clientId != clientId) throw _failure('ACTION_IO_UNAUTHORIZED');
        if (session.processState != 'queued') return false;
        (await _finish(executionId, exitCode: null, complete: true, failureCode: 'ACTION_CANCELLED')).getOrThrow();
        return true;
      }),
    );
    if (result.isSuccess() && result.getOrThrow()) {
      signalJournalCommit(executionId);
      _metrics?.recordExecutionOutcome(ActionIoExecutionOutcome.cancelled, captureComplete: true);
    }
    return result;
  }

  @override
  Future<Result<Unit>> finish(
    String executionId, {
    required int? exitCode,
    required bool complete,
    bool processTerminated = true,
    String? failureCode,
  }) async {
    final result = await _finish(
      executionId,
      exitCode: exitCode,
      complete: complete,
      processTerminated: processTerminated,
      failureCode: failureCode,
    );
    if (result.isSuccess()) {
      signalJournalCommit(executionId);
      final outcome = !processTerminated
          ? ActionIoExecutionOutcome.unknown
          : failureCode == 'ACTION_CANCELLED'
          ? ActionIoExecutionOutcome.cancelled
          : complete && exitCode == 0 && failureCode == null
          ? ActionIoExecutionOutcome.succeeded
          : ActionIoExecutionOutcome.failed;
      _metrics?.recordExecutionOutcome(outcome, captureComplete: complete);
    }
    return result;
  }

  Future<Result<Unit>> _finish(
    String executionId, {
    required int? exitCode,
    required bool complete,
    bool processTerminated = true,
    String? failureCode,
  }) => _guard(
    () => _db.transaction(() async {
      final session = await _session(executionId);
      if (!const {'capturing', 'draining'}.contains(session.captureState)) throw _failure('ACTION_IO_CAPTURE_CLOSED');
      if ((!complete && (failureCode == null || failureCode.isEmpty)) || (complete && !processTerminated)) {
        throw _failure('ACTION_IO_INVALID_INPUT');
      }
      await (_db.update(
        _db.actionIoMessages,
      )..where((m) => m.executionId.equals(executionId) & m.deliveryState.equals('writing'))).write(
        const ActionIoMessagesCompanion(
          deliveryState: Value('unknown'),
          confirmedBytes: Value(null),
          failureCode: Value('ACTION_OUTCOME_UNKNOWN'),
        ),
      );
      await (_db.update(
        _db.actionIoMessages,
      )..where((m) => m.executionId.equals(executionId) & m.deliveryState.equals('accepted'))).write(
        const ActionIoMessagesCompanion(
          deliveryState: Value('failed'),
          confirmedBytes: Value(0),
          failureCode: Value('ACTION_STDIN_CLOSED'),
        ),
      );
      var sequence = session.nextEventSequence;
      final now = DateTime.now();
      if (processTerminated) {
        await _db
            .into(_db.actionIoEvents)
            .insert(
              ActionIoEventsCompanion.insert(
                executionId: executionId,
                sequence: sequence++,
                eventType: 'process_exited',
                exitCode: Value(exitCode),
                createdAt: now,
              ),
            );
      }
      await _db
          .into(_db.actionIoEvents)
          .insert(
            ActionIoEventsCompanion.insert(
              executionId: executionId,
              sequence: sequence++,
              eventType: 'completed',
              outputComplete: Value(complete),
              failureCode: Value(failureCode),
              createdAt: now,
            ),
          );
      await (_db.update(_db.actionIoSessions)..where((s) => s.executionId.equals(executionId))).write(
        ActionIoSessionsCompanion(
          nextEventSequence: Value(sequence),
          processState: Value(processTerminated ? 'finished' : 'unknown'),
          captureState: Value(complete ? 'complete' : 'incomplete'),
          stdinState: Value(session.stdinState == 'closed' ? 'closed' : 'failed'),
          queuedInputBytes: const Value(0),
          queuedInputMessages: const Value(0),
          exitCode: Value(exitCode),
          failureCode: Value(failureCode),
          terminalAt: Value(processTerminated ? now : null),
          outputExpiresAt: Value(processTerminated ? now.add(ActionIoLimits.outputRetention) : null),
          dedupeExpiresAt: Value(processTerminated ? now.add(ActionIoLimits.deduplicationRetention) : null),
        ),
      );
      return unit;
    }),
  );

  Future<ActionIoSession> _session(String executionId) async {
    final session = await (_db.select(
      _db.actionIoSessions,
    )..where((s) => s.executionId.equals(executionId))).getSingleOrNull();
    if (session == null) throw _failure('ACTION_IO_UNAUTHORIZED');
    return session;
  }

  Future<Result<T>> _guard<T extends Object>(Future<T> Function() action) async {
    try {
      return Success(await action());
    } on ActionFailure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'The I/O journal is unavailable.',
          code: 'ACTION_IO_STORAGE_FAILED',
          context: {'retryable': false, 'cause_type': error.runtimeType.toString()},
        ),
      );
    }
  }

  ActionRuntimeFailure _failure(String code) => ActionRuntimeFailure.withContext(
    message: 'The I/O output cannot be stored or delivered.',
    code: code,
    context: {'retryable': false},
  );
}
