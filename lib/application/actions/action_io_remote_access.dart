import 'dart:async';

import 'package:plug_agente/application/actions/action_io_authorization.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_execution_snapshot.dart';
import 'package:plug_agente/domain/actions/action_io_journal.dart';
import 'package:plug_agente/domain/actions/action_io_journal_changes.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/actions/action_io_session_reference.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_action_io_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_metrics.dart';
import 'package:plug_agente/domain/repositories/i_action_io_output_journal.dart';
import 'package:plug_agente/domain/repositories/i_action_io_session_lookup.dart';
import 'package:result_dart/result_dart.dart';

/// Shared across connections so reader quotas cannot be bypassed by reconnecting.
final class ActionIoRemoteAccess {
  ActionIoRemoteAccess({
    required this.installationId,
    required ActionIoAuthorization authorization,
    required IActionIoJournal input,
    required IActionIoOutputJournal output,
    required IActionIoSessionLookup sessions,
    DateTime Function()? now,
    Result<bool> Function(String executionId)? requestCancel,
    IActionIoMetrics? metrics,
  }) : _authorization = authorization,
       _input = input,
       _output = output,
       _sessions = sessions,
       _requestCancel = requestCancel,
       _metrics = metrics,
       _now = now ?? DateTime.now;

  final String installationId;
  final IActionIoMetrics? _metrics;
  final Result<bool> Function(String)? _requestCancel;
  final ActionIoAuthorization _authorization;
  final IActionIoJournal _input;
  final IActionIoOutputJournal _output;
  final IActionIoSessionLookup _sessions;
  final DateTime Function() _now;
  final Map<(String, String), _ReadReservation> _readers = {};
  final Map<String, int> _clients = {};
  final Map<String, int> _connections = {};
  static const _pollInterval = Duration(milliseconds: 100);

  Future<Result<ActionIoExecutionSnapshot>> cancel({
    required String executionId,
    required String agentId,
    required String credential,
    bool Function()? isRequestActive,
  }) => _guard(() async {
    final owner = await _authorize(executionId, agentId, credential, ActionIoOperation.cancel);
    _requireActiveRequest(isRequestActive);
    final queued = (await _output.cancelQueued(executionId, owner.clientId)).getOrThrow();
    if (!queued) {
      final snapshot = (await _sessions.getExecutionSnapshot(executionId)).getOrThrow();
      if (snapshot.processState != 'finished' && snapshot.processState != 'unknown') {
        await _authorize(executionId, agentId, credential, ActionIoOperation.cancel);
        _requireActiveRequest(isRequestActive);
        final request = _requestCancel;
        if (request == null || !request(executionId).getOrThrow()) {
          throw _failure('ACTION_OUTCOME_UNKNOWN');
        }
      }
    }
    final snapshot = (await _sessions.getExecutionSnapshot(executionId)).getOrThrow();
    await _authorize(executionId, agentId, credential, ActionIoOperation.cancel);
    return snapshot;
  });

  Future<Result<ActionIoExecutionSnapshot>> execution({
    required String executionId,
    required String agentId,
    required String credential,
  }) => _guard(() async {
    await _authorize(executionId, agentId, credential, ActionIoOperation.getExecution);
    final snapshot = (await _sessions.getExecutionSnapshot(executionId)).getOrThrow();
    await _authorize(executionId, agentId, credential, ActionIoOperation.getExecution);
    return snapshot;
  });

  Future<Result<ActionIoMessageReceipt>> send({
    required String executionId,
    required String agentId,
    required String credential,
    required String messageId,
    required int sequence,
    required List<int> bytes,
    bool close = false,
    bool Function()? isRequestActive,
  }) => _guard(() async {
    final session = await _authorize(
      executionId,
      agentId,
      credential,
      close ? ActionIoOperation.closeInput : ActionIoOperation.sendInput,
    );
    _requireActiveRequest(isRequestActive);
    return (await _input.admitInput(
      executionId: executionId,
      clientId: session.clientId,
      messageId: messageId,
      sequence: sequence,
      bytes: bytes,
      close: close,
    )).getOrThrow();
  });

  void _requireActiveRequest(bool Function()? isActive) {
    if (isActive != null && !isActive()) throw _failure('ACTION_IO_REQUEST_EXPIRED');
  }

  Future<Result<ActionIoMessageReceipt>> inputStatus({
    required String executionId,
    required String agentId,
    required String credential,
    required String messageId,
  }) => _guard(() async {
    final session = await _authorize(executionId, agentId, credential, ActionIoOperation.getInputStatus);
    return (await _input.inputStatus(executionId, session.clientId, messageId)).getOrThrow();
  });

  Future<Result<ActionIoExecutionLookup>> find({
    required String agentId,
    required String credential,
    required String actionId,
    required String idempotencyKey,
  }) => _guard(() async {
    final principal = (await _authorization.authorize(
      credential: credential,
      agentId: agentId,
      actionId: actionId,
      operation: ActionIoOperation.findExecution,
    )).getOrThrow();
    return (await _sessions.findExecution(
      installationId: installationId,
      agentId: agentId,
      clientId: principal.clientId,
      actionId: actionId,
      idempotencyKey: idempotencyKey,
    )).getOrThrow();
  });

  Future<Result<ActionIoReadPage>> read({
    required String executionId,
    required String agentId,
    required String credential,
    required String connectionId,
    required int afterSequence,
    required int maxBytes,
    required Duration wait,
    required DateTime deadline,
    bool Function()? isCancelled,
    void Function()? onReadWait,
  }) => _guard(() async {
    if (wait < Duration.zero ||
        wait > ActionIoLimits.pollTimeout ||
        connectionId.isEmpty ||
        maxBytes < ActionIoLimits.blockBytes ||
        maxBytes > ActionIoLimits.pageBytes ||
        afterSequence < 0) {
      throw _failure('ACTION_IO_INVALID_INPUT');
    }
    final session = await _authorize(executionId, agentId, credential, ActionIoOperation.readIo);
    final reader = (executionId, session.clientId);
    // Cancelled waits must not retain admission capacity until their timer wakes.
    for (final entry in _readers.entries.toList()) {
      if (entry.value.isCancelled?.call() ?? false) _releaseRead(entry.key, entry.value);
    }
    if (_readers.containsKey(reader) ||
        _readers.length >= ActionIoLimits.readersPerAgent ||
        (_clients[session.clientId] ?? 0) >= ActionIoLimits.readersPerClient ||
        (_connections[connectionId] ?? 0) >= ActionIoLimits.readersPerConnection) {
      throw _failure('ACTION_IO_READER_LIMIT');
    }
    final reservation = _ReadReservation(connectionId, isCancelled);
    _readers[reader] = reservation;
    _metrics?.setActiveReaders(_readers.length);
    _clients.update(session.clientId, (count) => count + 1, ifAbsent: () => 1);
    _connections.update(connectionId, (count) => count + 1, ifAbsent: () => 1);
    final journal = _output;
    final changes = wait > Duration.zero && journal is IActionIoJournalChanges
        ? (journal as IActionIoJournalChanges).observeChanges(executionId)
        : null;
    try {
      final available = deadline.difference(_now()) - ActionIoLimits.responseReserve;
      final effective = available <= Duration.zero ? Duration.zero : (wait < available ? wait : available);
      final until = _now().add(effective);
      var waitingNotified = false;
      while (true) {
        if (isCancelled?.call() ?? false) throw _failure('ACTION_IO_READ_CANCELLED');
        if (!_now().isBefore(deadline)) throw _failure('ACTION_TIMEOUT');
        final page = (await _output.read(
          executionId: executionId,
          clientId: session.clientId,
          afterSequence: afterSequence,
          maxBytes: maxBytes,
        )).getOrThrow();
        final remaining = until.difference(_now());
        if (page.events.isNotEmpty || page.terminal || remaining <= Duration.zero) {
          // Never return data using authority captured before a long poll.
          await _authorize(executionId, agentId, credential, ActionIoOperation.readIo);
          if (isCancelled?.call() ?? false) throw _failure('ACTION_IO_READ_CANCELLED');
          if (!_now().isBefore(deadline)) throw _failure('ACTION_TIMEOUT');
          _metrics?.recordReadBytes(
            page.events.whereType<ActionIoOutputEvent>().fold(0, (sum, event) => sum + event.bytes.length),
          );
          return page;
        }
        if (!waitingNotified) {
          waitingNotified = true;
          onReadWait?.call();
        }
        final fallback = remaining < _pollInterval ? remaining : _pollInterval;
        await (changes?.wait(fallback) ?? Future<void>.delayed(fallback));
      }
    } finally {
      changes?.close();
      _releaseRead(reader, reservation);
    }
  });

  void _releaseRead((String, String) reader, _ReadReservation reservation) {
    if (!identical(_readers[reader], reservation)) return;
    _readers.remove(reader);
    _metrics?.setActiveReaders(_readers.length);
    _decrement(_clients, reader.$2);
    _decrement(_connections, reservation.connectionId);
  }

  Future<ActionIoSessionReference> _authorize(
    String executionId,
    String agentId,
    String credential,
    ActionIoOperation operation,
  ) async {
    final session = (await _sessions.getSessionReference(executionId)).getOrThrow();
    if (session.installationId != installationId || session.agentId != agentId) {
      throw _failure('ACTION_IO_UNAUTHORIZED');
    }
    (await _authorization.authorize(
      credential: credential,
      agentId: agentId,
      actionId: session.actionId,
      operation: operation,
      ownerClientId: session.clientId,
    )).getOrThrow();
    return session;
  }

  void _decrement(Map<String, int> counts, String key) {
    final next = counts[key]! - 1;
    if (next == 0) {
      counts.remove(key);
    } else {
      counts[key] = next;
    }
  }

  Future<Result<T>> _guard<T extends Object>(Future<T> Function() body) async {
    try {
      final value = await body();
      _metrics?.recordRemoteOutcome(ActionIoRemoteOutcome.success);
      return Success(value);
    } on domain.Failure catch (failure) {
      _metrics?.recordRemoteOutcome(switch (failure.code) {
        'ACTION_IO_UNAUTHORIZED' => ActionIoRemoteOutcome.unauthorized,
        'ACTION_IO_READER_LIMIT' ||
        'ACTION_IO_STORAGE_QUOTA_EXCEEDED' ||
        'ACTION_IO_CONCURRENCY_LIMIT' => ActionIoRemoteOutcome.limited,
        'ACTION_IO_READ_CANCELLED' => ActionIoRemoteOutcome.cancelled,
        'ACTION_OUTCOME_UNKNOWN' => ActionIoRemoteOutcome.unknown,
        _ => ActionIoRemoteOutcome.failed,
      });
      return Failure(failure);
    } on Exception {
      _metrics?.recordRemoteOutcome(ActionIoRemoteOutcome.failed);
      return Failure(_failure('ACTION_IO_UNAVAILABLE'));
    }
  }

  ActionFailure _failure(String code) => ActionRuntimeFailure.withContext(
    message: 'The requested I/O operation could not be completed.',
    code: code,
    context: {'retryable': false},
  );
}

final class _ReadReservation {
  const _ReadReservation(this.connectionId, this.isCancelled);
  final String connectionId;
  final bool Function()? isCancelled;
}
