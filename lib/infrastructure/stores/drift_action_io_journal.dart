import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_execution_snapshot.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_journal_changes.dart';
import 'package:plug_agente/domain/actions/action_io_session_reference.dart';
import 'package:plug_agente/domain/repositories/i_action_io_execution_ownership.dart';
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_history.dart';
import 'package:plug_agente/domain/repositories/i_action_io_metrics.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_lookup.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_budget.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_cipher.dart';
import 'package:result_dart/result_dart.dart';
import 'package:uuid/uuid.dart';

final class DriftActionIoJournal
    with ActionIoJournalChanges
    implements IActionIoJournal, IActionIoSessionLookup, IActionIoLocalHistory, IActionIoExecutionOwnership {
  DriftActionIoJournal(
    this._db,
    this._cipher, {
    DateTime Function()? now,
    int Function()? concurrencyLimit,
    Future<Result<Unit>> Function(int)? physicalCapacity,
    IActionIoMetrics? metrics,
  }) : _metrics = metrics,
       _physicalCapacity = physicalCapacity,
       _now = now ?? DateTime.now,
       _concurrencyLimit = concurrencyLimit ?? (() => ActionIoLimits.concurrentExecutions);
  final Future<Result<Unit>> Function(int)? _physicalCapacity;
  final IActionIoMetrics? _metrics;
  final ActionIoJournalDatabase _db;
  final ActionIoPayloadCipher _cipher;
  final DateTime Function() _now;
  final int Function() _concurrencyLimit;

  @override
  Future<Result<bool>> ownsExecution(String executionId) => _guard(() async {
    final row =
        await (_db.select(_db.actionIoSessions)
              ..where((row) => row.executionId.equals(executionId))
              ..limit(1))
            .getSingleOrNull();
    return row != null;
  });

  @override
  Future<Result<List<ActionIoExecutionSnapshot>>> listExecutionSnapshots({
    required int limit,
    ActionIoHistoryCursor? after,
    String? actionId,
    String? idempotencyKey,
    DateTime? requestedAfter,
  }) => _guard(() async {
    if (limit < 1 || limit > IActionIoLocalHistory.maxPageSize) throw _refusal('ACTION_IO_INVALID_HISTORY_LIMIT');
    final query = _db.select(_db.actionIoSessions);
    if (after != null) {
      query.where(
        (row) =>
            row.createdAt.isSmallerThanValue(after.createdAt) |
            (row.createdAt.equals(after.createdAt) & row.executionId.isBiggerThanValue(after.executionId)),
      );
    }
    if (actionId != null) query.where((row) => row.actionId.equals(actionId));
    if (idempotencyKey != null) query.where((row) => row.idempotencyKey.equals(idempotencyKey));
    if (requestedAfter != null) query.where((row) => row.createdAt.isBiggerOrEqualValue(requestedAfter));
    query
      ..orderBy([(row) => OrderingTerm.desc(row.createdAt), (row) => OrderingTerm.asc(row.executionId)])
      ..limit(limit);
    return _snapshots(await query.get());
  });

  @override
  Future<Result<ActionIoExecutionSnapshot>> getExecutionSnapshot(String executionId) => _guard(() async {
    final row = await _session(executionId);
    return (await _snapshots([row])).single;
  });

  Future<List<ActionIoExecutionSnapshot>> _snapshots(List<ActionIoSession> rows) async {
    if (rows.isEmpty) return [];
    final messages = _db.actionIoMessages;
    final sum = messages.confirmedBytes.sum();
    final query = _db.selectOnly(messages)
      ..addColumns([messages.executionId, sum])
      ..where(messages.executionId.isIn(rows.map((row) => row.executionId)))
      ..groupBy([messages.executionId]);
    final totals = {for (final row in await query.get()) row.read(messages.executionId): row.read(sum) ?? 0};
    return [for (final row in rows) _snapshot(row, totals[row.executionId] ?? 0)];
  }

  ActionIoExecutionSnapshot _snapshot(ActionIoSession row, int confirmedInputBytes) => ActionIoExecutionSnapshot(
    session: _reference(row),
    idempotencyKey: row.idempotencyKey,
    createdAt: row.createdAt,
    processState: row.processState,
    stdinState: row.stdinState,
    captureState: row.captureState,
    outputExpired: row.outputExpired,
    admittedInputBytes: row.admittedInputBytes,
    confirmedInputBytes: confirmedInputBytes,
    stdoutBytes: row.stdoutBytes,
    stderrBytes: row.stderrBytes,
    nextInputSequence: row.nextInputSequence,
    terminalAt: row.terminalAt,
    exitCode: row.exitCode,
    failureCode: row.failureCode,
  );

  @override
  Future<Result<ActionIoSessionReference>> getSessionReference(String executionId) =>
      _guard(() async => _reference(await _session(executionId)));

  @override
  Future<Result<ActionIoExecutionLookup>> findExecution({
    required String installationId,
    required String agentId,
    required String clientId,
    required String actionId,
    required String idempotencyKey,
  }) => _guard(() async {
    final row =
        await (_db.select(_db.actionIoSessions)..where(
              (s) =>
                  s.installationId.equals(installationId) &
                  s.agentId.equals(agentId) &
                  s.clientId.equals(clientId) &
                  s.actionId.equals(actionId) &
                  s.idempotencyKey.equals(idempotencyKey),
            ))
            .getSingleOrNull();
    return ActionIoExecutionLookup(row == null ? null : _reference(row));
  });

  ActionIoSessionReference _reference(ActionIoSession row) => ActionIoSessionReference(
    executionId: row.executionId,
    installationId: row.installationId,
    agentId: row.agentId,
    clientId: row.clientId,
    actionId: row.actionId,
    triggerId: row.triggerId,
    definitionHash: row.definitionHash,
    actionType: row.actionType,
  );

  String _intentFingerprint(ActionIoSessionIntent intent, ActionIoConfiguration? io) {
    if (io == null) return intent.fingerprint;
    final initial = io.initialInput;
    if (initial != null && initial.length > ActionIoLimits.blockBytes) {
      throw _refusal('ACTION_IO_INVALID_INPUT');
    }
    return sha256
        .convert(
          utf8.encode(
            jsonEncode([
              'action-io-intent-v1',
              intent.fingerprint,
              io.closeInput,
              if (initial == null) null else base64Encode(initial),
            ]),
          ),
        )
        .toString();
  }

  @override
  Future<Result<ActionIoExecutionLookup>> previewClaim(
    ActionIoSessionIntent intent, {
    required ActionIoConfiguration io,
  }) => _guard(() async {
    final fingerprint = _intentFingerprint(intent, io);
    final existing =
        await (_db.select(_db.actionIoSessions)..where(
              (s) =>
                  s.installationId.equals(intent.installationId) &
                  s.agentId.equals(intent.agentId) &
                  s.clientId.equals(intent.clientId) &
                  s.actionId.equals(intent.actionId) &
                  s.idempotencyKey.equals(intent.idempotencyKey),
            ))
            .getSingleOrNull();
    if (existing == null) return const ActionIoExecutionLookup(null);
    if (existing.fingerprint != fingerprint) throw _refusal('ACTION_INPUT_CONFLICT');
    return ActionIoExecutionLookup(_reference(existing));
  });

  @override
  Future<Result<ActionIoSessionClaim>> claim(ActionIoSessionIntent intent, {ActionIoConfiguration? io}) async {
    final result = await _claim(intent, io: io);
    if (result.isSuccess() && result.getOrThrow().created) {
      _metrics?.recordAdmittedInputBytes(io?.initialInput?.length ?? 0);
    }
    return result;
  }

  Future<Result<ActionIoSessionClaim>> _claim(ActionIoSessionIntent intent, {ActionIoConfiguration? io}) => _guard(
    () => _db.transaction(() async {
      final initial = io?.initialInput;
      if (initial != null && initial.length > ActionIoLimits.blockBytes) throw _refusal('ACTION_IO_INVALID_INPUT');
      final fingerprint = _intentFingerprint(intent, io);
      ActionIoSessionClaim result(String id, {required bool created}) => ActionIoSessionClaim(
        executionId: id,
        created: created,
        initialMessageId: initial == null ? null : ActionIoLimits.initialMessageId,
        closeMessageId: io?.closeInput == true ? ActionIoLimits.closeMessageId : null,
      );
      final existing =
          await (_db.select(_db.actionIoSessions)..where(
                (s) =>
                    s.installationId.equals(intent.installationId) &
                    s.agentId.equals(intent.agentId) &
                    s.clientId.equals(intent.clientId) &
                    s.actionId.equals(intent.actionId) &
                    s.idempotencyKey.equals(intent.idempotencyKey),
              ))
              .getSingleOrNull();
      if (existing != null) {
        if (existing.fingerprint != fingerprint) throw _refusal('ACTION_INPUT_CONFLICT');
        return result(existing.executionId, created: false);
      }
      (await _physicalCapacity?.call(initial?.length ?? 0))?.getOrThrow();
      await _db
          .into(_db.actionIoSessions)
          .insert(
            ActionIoSessionsCompanion.insert(
              executionId: intent.executionId,
              installationId: intent.installationId,
              agentId: intent.agentId,
              clientId: intent.clientId,
              actionId: intent.actionId,
              idempotencyKey: intent.idempotencyKey,
              fingerprint: fingerprint,
              triggerId: intent.triggerId,
              definitionHash: intent.definitionHash,
              actionType: Value(intent.actionType),
              processState: 'queued',
              stdinState: 'pending',
              captureState: 'capturing',
              createdAt: _now(),
            ),
          );
      var sequence = 0;
      if (initial != null) {
        (await _admitInput(
          executionId: intent.executionId,
          clientId: intent.clientId,
          messageId: ActionIoLimits.initialMessageId,
          sequence: sequence++,
          bytes: initial,
          internalMessage: true,
          standaloneAdmission: false,
        )).getOrThrow();
      }
      if (io?.closeInput == true) {
        (await _admitInput(
          executionId: intent.executionId,
          clientId: intent.clientId,
          messageId: ActionIoLimits.closeMessageId,
          sequence: sequence,
          bytes: const [],
          close: true,
          internalMessage: true,
          standaloneAdmission: false,
        )).getOrThrow();
      }
      return result(intent.executionId, created: true);
    }),
  );

  @override
  Future<Result<ActionIoMessageReceipt>> admitInput({
    required String executionId,
    required String clientId,
    required String messageId,
    required int sequence,
    required List<int> bytes,
    bool close = false,
    bool internalMessage = false,
  }) => _admitInput(
    executionId: executionId,
    clientId: clientId,
    messageId: messageId,
    sequence: sequence,
    bytes: bytes,
    close: close,
    internalMessage: internalMessage,
  );

  Future<Result<ActionIoMessageReceipt>> _admitInput({
    required String executionId,
    required String clientId,
    required String messageId,
    required int sequence,
    required List<int> bytes,
    bool close = false,
    bool internalMessage = false,
    bool standaloneAdmission = true,
  }) async {
    final ownedBytes = Uint8List.fromList(bytes);
    var created = false;
    final result = await _guard(
      () => _db.transaction(() async {
        if (messageId.isEmpty ||
            sequence < 0 ||
            sequence > 9007199254740991 ||
            ownedBytes.length > ActionIoLimits.blockBytes ||
            (close && ownedBytes.isNotEmpty) ||
            (!internalMessage && messageId.startsWith(ActionIoLimits.reservedMessagePrefix))) {
          throw _refusal('ACTION_IO_INVALID_INPUT');
        }
        final session = await (_db.select(
          _db.actionIoSessions,
        )..where((s) => s.executionId.equals(executionId) & s.clientId.equals(clientId))).getSingleOrNull();
        if (session == null) throw _refusal('ACTION_IO_UNAUTHORIZED');
        final fingerprint = sha256
            .convert(utf8.encode(jsonEncode([sequence, close, base64Encode(ownedBytes)])))
            .toString();
        final previous = await (_db.select(
          _db.actionIoMessages,
        )..where((m) => m.executionId.equals(executionId) & m.messageId.equals(messageId))).getSingleOrNull();
        if (previous != null) {
          if (previous.fingerprint != fingerprint) throw _refusal('ACTION_INPUT_CONFLICT');
          return _receipt(previous, session);
        }
        if (!const {'pending', 'open'}.contains(session.stdinState) || session.terminalAt != null) {
          throw _refusal('ACTION_STDIN_CLOSED');
        }
        if (sequence != session.nextInputSequence) throw _refusal('ACTION_INPUT_SEQUENCE_INVALID');
        if (session.queuedInputMessages >= ActionIoLimits.queuedMessages ||
            session.queuedInputBytes + ownedBytes.length > ActionIoLimits.queuedBytes) {
          throw _refusal('ACTION_INPUT_QUEUE_FULL');
        }
        if (session.nextInputSequence >= ActionIoLimits.executionMessages ||
            session.admittedInputBytes + session.stdoutBytes + session.stderrBytes + ownedBytes.length >
                ActionIoLimits.executionBytes) {
          throw _refusal('ACTION_IO_INVALID_INPUT');
        }
        (await _physicalCapacity?.call(ownedBytes.length))?.getOrThrow();
        await requireActionIoPayloadCapacity(_db, ownedBytes.length);
        final context = ActionIoPayloadCipher.context(
          executionId: executionId,
          channel: 'stdin',
          messageId: messageId,
          sequence: sequence,
          offset: 0,
        );
        final encrypted = await _cipher.encrypt(ownedBytes, context: context);
        if (encrypted.isError()) throw encrypted.exceptionOrNull()!;
        final payload = encrypted.getOrThrow();
        final payloadId = const Uuid().v4();
        await _db
            .into(_db.actionIoPayloads)
            .insert(
              ActionIoPayloadsCompanion.insert(
                payloadId: payloadId,
                executionId: executionId,
                keyId: payload.keyId,
                nonce: payload.nonce,
                ciphertext: payload.ciphertext,
                authenticationTag: payload.tag,
                authenticatedContext: payload.context,
                plaintextBytes: ownedBytes.length,
              ),
            );
        await _db
            .into(_db.actionIoMessages)
            .insert(
              ActionIoMessagesCompanion.insert(
                executionId: executionId,
                messageId: messageId,
                sequence: sequence,
                fingerprint: fingerprint,
                closesInput: close,
                deliveryState: 'accepted',
                confirmedBytes: const Value(0),
                inputBytes: ownedBytes.length,
                payloadId: Value(payloadId),
                admittedAt: _now(),
              ),
            );
        final stdinState = close ? 'closing' : session.stdinState;
        await (_db.update(_db.actionIoSessions)..where((s) => s.executionId.equals(executionId))).write(
          ActionIoSessionsCompanion(
            nextInputSequence: Value(sequence + 1),
            stdinState: Value(stdinState),
            admittedInputBytes: Value(session.admittedInputBytes + ownedBytes.length),
            queuedInputBytes: Value(session.queuedInputBytes + ownedBytes.length),
            queuedInputMessages: Value(session.queuedInputMessages + 1),
          ),
        );
        created = true;
        return ActionIoMessageReceipt(
          executionId: executionId,
          messageId: messageId,
          sequence: sequence,
          state: ActionIoDeliveryState.accepted,
          confirmedBytes: 0,
          nextInputSequence: sequence + 1,
          stdinState: ActionIoStdinState.values.byName(stdinState),
        );
      }),
    );
    // Initial messages belong to the outer claim transaction and precede worker startup.
    if (result.isSuccess() && created && standaloneAdmission) {
      signalJournalCommit(executionId);
      _metrics?.recordAdmittedInputBytes(ownedBytes.length);
    }
    return result;
  }

  @override
  Future<Result<ActionIoMessageReceipt>> inputStatus(String executionId, String clientId, String messageId) => _guard(
    () => _db.transaction(() async {
      final session = await _session(executionId);
      if (session.clientId != clientId) throw _refusal('ACTION_IO_UNAUTHORIZED');
      final message = await (_db.select(
        _db.actionIoMessages,
      )..where((m) => m.executionId.equals(executionId) & m.messageId.equals(messageId))).getSingleOrNull();
      if (message == null) throw _refusal('ACTION_IO_MESSAGE_NOT_FOUND');
      return _receipt(message, session);
    }),
  );

  @override
  Future<Result<Unit>> markStarting(String executionId) => _transitionProcess(executionId, 'queued', 'starting');

  @override
  Future<Result<Unit>> markRunning(String executionId) => _transitionProcess(executionId, 'starting', 'running');

  Future<Result<Unit>> _transitionProcess(String executionId, String from, String to) => _guard(
    () => _db.transaction(() async {
      final session = await _session(executionId);
      if (session.processState != from) throw _refusal('ACTION_OUTCOME_UNKNOWN');
      if (to == 'starting') {
        final configured = _concurrencyLimit();
        if (configured < 1) throw _refusal('ACTION_IO_CONCURRENCY_LIMIT');
        final limit = configured < ActionIoLimits.concurrentExecutions
            ? configured
            : ActionIoLimits.concurrentExecutions;
        // Unknown executions retain capacity: restart cannot prove their process
        // tree stopped. The same transaction reserves the slot before spawn.
        final reserved =
            await (_db.select(_db.actionIoSessions)
                  ..where((s) => s.processState.isIn(['starting', 'running', 'stopping', 'unknown']))
                  ..limit(limit))
                .get();
        if (reserved.length >= limit) throw _refusal('ACTION_IO_CONCURRENCY_LIMIT');
      }
      await (_db.update(_db.actionIoSessions)..where((s) => s.executionId.equals(executionId))).write(
        ActionIoSessionsCompanion(
          processState: Value(to),
          stdinState: Value(to == 'running' && session.stdinState == 'pending' ? 'open' : session.stdinState),
        ),
      );
      return unit;
    }),
  );

  @override
  Future<Result<ActionIoInputPoll>> beginNextInput(String executionId) => _guard(
    () => _db.transaction(() async {
      final session = await _session(executionId);
      if (session.processState != 'running' || !const {'open', 'closing'}.contains(session.stdinState)) {
        return const ActionIoInputPoll(null);
      }
      final next =
          await (_db.select(_db.actionIoMessages)
                ..where((m) => m.executionId.equals(executionId) & m.deliveryState.isIn(['accepted', 'writing']))
                ..orderBy([(m) => OrderingTerm.asc(m.sequence)])
                ..limit(1))
              .getSingleOrNull();
      if (next == null || next.deliveryState == 'writing') return const ActionIoInputPoll(null);
      final payload = await (_db.select(
        _db.actionIoPayloads,
      )..where((p) => p.payloadId.equals(next.payloadId ?? ''))).getSingleOrNull();
      if (payload == null) throw _refusal('ACTION_IO_INTEGRITY_FAILED');
      final expected = ActionIoPayloadCipher.context(
        executionId: executionId,
        channel: 'stdin',
        messageId: next.messageId,
        sequence: next.sequence,
        offset: 0,
      );
      final decoded = await _cipher.decrypt(
        ActionIoEncryptedPayload(
          keyId: payload.keyId,
          nonce: payload.nonce,
          ciphertext: payload.ciphertext,
          tag: payload.authenticationTag,
          context: payload.authenticatedContext,
        ),
        expectedContext: expected,
      );
      if (decoded.isError()) throw decoded.exceptionOrNull()!;
      if (decoded.getOrThrow().length != next.inputBytes) throw _refusal('ACTION_IO_INTEGRITY_FAILED');
      await (_db.update(_db.actionIoMessages)
            ..where((m) => m.executionId.equals(executionId) & m.messageId.equals(next.messageId)))
          .write(const ActionIoMessagesCompanion(deliveryState: Value('writing')));
      return ActionIoInputPoll(
        ActionIoPendingInput(
          receipt: _receipt(next.copyWith(deliveryState: 'writing'), session),
          close: next.closesInput,
          bytes: decoded.getOrThrow(),
        ),
      );
    }),
  );

  @override
  Future<Result<ActionIoMessageReceipt>> finishInput(
    String executionId,
    String messageId,
    ActionIoDeliveryState state, {
    required int? confirmedBytes,
    String? failureCode,
  }) async {
    var changed = false;
    final result = await _guard(
      () => _db.transaction(() async {
        final session = await _session(executionId);
        final message = await (_db.select(
          _db.actionIoMessages,
        )..where((m) => m.executionId.equals(executionId) & m.messageId.equals(messageId))).getSingleOrNull();
        if (message == null) throw _refusal('ACTION_IO_MESSAGE_NOT_FOUND');
        if (!const {
              ActionIoDeliveryState.written,
              ActionIoDeliveryState.failed,
              ActionIoDeliveryState.unknown,
            }.contains(state) ||
            (confirmedBytes != null && (confirmedBytes < 0 || confirmedBytes > message.inputBytes)) ||
            (state == ActionIoDeliveryState.written && confirmedBytes != message.inputBytes)) {
          throw _refusal('ACTION_IO_INVALID_INPUT');
        }
        if (message.deliveryState != 'writing') {
          if (message.deliveryState == state.name &&
              message.confirmedBytes == confirmedBytes &&
              message.failureCode == failureCode) {
            return _receipt(message, session);
          }
          throw _refusal('ACTION_INPUT_CONFLICT');
        }
        final stdinState = state != ActionIoDeliveryState.written
            ? 'failed'
            : (message.closesInput ? 'closed' : session.stdinState);
        await (_db.update(
          _db.actionIoMessages,
        )..where((m) => m.executionId.equals(executionId) & m.messageId.equals(messageId))).write(
          ActionIoMessagesCompanion(
            deliveryState: Value(state.name),
            confirmedBytes: Value(confirmedBytes),
            failureCode: Value(failureCode),
          ),
        );
        await (_db.update(_db.actionIoSessions)..where((s) => s.executionId.equals(executionId))).write(
          ActionIoSessionsCompanion(
            stdinState: Value(stdinState),
            queuedInputBytes: Value(session.queuedInputBytes - message.inputBytes),
            queuedInputMessages: Value(session.queuedInputMessages - 1),
          ),
        );
        changed = true;
        return _receipt(
          message.copyWith(deliveryState: state.name, confirmedBytes: Value(confirmedBytes)),
          session.copyWith(stdinState: stdinState),
        );
      }),
    );
    if (result.isSuccess() && changed) {
      _metrics?.recordInputOutcome(switch (state) {
        ActionIoDeliveryState.written => ActionIoInputOutcome.written,
        ActionIoDeliveryState.failed => ActionIoInputOutcome.failed,
        ActionIoDeliveryState.unknown => ActionIoInputOutcome.unknown,
        _ => throw StateError('Committed input outcome must be terminal.'),
      }, confirmedBytes: confirmedBytes);
    }
    return result;
  }

  @override
  Future<Result<int>> reconcileInterrupted() async {
    final result = await _reconcileInterrupted();
    if (result.isSuccess()) _metrics?.recordInterruptedExecutions(result.getOrThrow());
    return result;
  }

  Future<Result<int>> _reconcileInterrupted() => _guard(
    () => _db.transaction(() async {
      final active = await (_db.select(
        _db.actionIoSessions,
      )..where((s) => s.processState.isIn(['queued', 'starting', 'running', 'stopping']))).get();
      for (final session in active) {
        await (_db.update(
          _db.actionIoMessages,
        )..where((m) => m.executionId.equals(session.executionId) & m.deliveryState.equals('writing'))).write(
          const ActionIoMessagesCompanion(
            deliveryState: Value('unknown'),
            confirmedBytes: Value(null),
            failureCode: Value('ACTION_OUTCOME_UNKNOWN'),
          ),
        );
        await (_db.update(
          _db.actionIoMessages,
        )..where((m) => m.executionId.equals(session.executionId) & m.deliveryState.equals('accepted'))).write(
          const ActionIoMessagesCompanion(
            deliveryState: Value('failed'),
            confirmedBytes: Value(0),
            failureCode: Value('ACTION_IO_INTERRUPTED'),
          ),
        );
        await (_db.update(_db.actionIoSessions)..where((s) => s.executionId.equals(session.executionId))).write(
          const ActionIoSessionsCompanion(
            processState: Value('unknown'),
            stdinState: Value('failed'),
            captureState: Value('incomplete'),
            queuedInputMessages: Value(0),
            queuedInputBytes: Value(0),
            failureCode: Value('ACTION_OUTCOME_UNKNOWN'),
          ),
        );
      }
      return active.length;
    }),
  );

  Future<ActionIoSession> _session(String executionId) async {
    final session = await (_db.select(
      _db.actionIoSessions,
    )..where((s) => s.executionId.equals(executionId))).getSingleOrNull();
    if (session == null) throw _refusal('ACTION_IO_UNAUTHORIZED');
    return session;
  }

  ActionIoMessageReceipt _receipt(ActionIoMessage message, ActionIoSession session) => ActionIoMessageReceipt(
    executionId: message.executionId,
    messageId: message.messageId,
    sequence: message.sequence,
    state: ActionIoDeliveryState.values.byName(message.deliveryState),
    confirmedBytes: message.confirmedBytes,
    nextInputSequence: session.nextInputSequence,
    stdinState: ActionIoStdinState.values.byName(session.stdinState),
  );

  Future<Result<T>> _guard<T extends Object>(Future<T> Function() operation) async {
    try {
      return Success(await operation());
    } on ActionFailure catch (failure) {
      return Failure(failure);
    } on Exception catch (error) {
      return Failure(
        ActionRuntimeFailure.withContext(
          message: 'The I/O journal could not persist the operation.',
          code: 'ACTION_IO_STORAGE_FAILED',
          context: {'cause_type': error.runtimeType.toString(), 'retryable': false},
        ),
      );
    }
  }

  ActionValidationFailure _refusal(String code) => ActionValidationFailure.withContext(
    message: 'The I/O request cannot be admitted.',
    code: code,
    context: {'phase': 'admission', 'effects_possible': false, 'retryable': false},
  );
}
