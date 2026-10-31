import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show BooleanExpressionOperators;
import 'package:drift/native.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/domain/actions/action_io_execution_snapshot.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/repositories/i_action_io_execution_ownership.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_history.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_output.dart';
import 'package:plug_agente/domain/repositories/i_action_io_metrics.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_database.dart';
import 'package:plug_agente/infrastructure/stores/action_io_journal_retention.dart';
import 'package:plug_agente/infrastructure/stores/action_io_output_journal.dart';
import 'package:plug_agente/infrastructure/stores/action_io_payload_budget.dart';
import 'package:plug_agente/infrastructure/stores/action_io_physical_budget.dart';
import 'package:plug_agente/infrastructure/stores/action_io_secure_key_store.dart';
import 'package:plug_agente/infrastructure/stores/drift_action_io_journal.dart';
import 'package:result_dart/result_dart.dart';

/// Owns the journal for its entire lifetime, including recovery and maintenance.
/// The execution coordinator must drain native workers before calling [close].
final class ActionIoJournalRuntime implements IActionIoLocalHistory, IActionIoLocalOutput, IActionIoExecutionOwnership {
  ActionIoJournalRuntime(
    this.path, {
    int Function()? concurrencyLimit,
    ActionIoSecureKeyStore? keyStore,
    Future<int?> Function(String)? freeBytes,
    IActionIoMetrics? metrics,
    DateTime Function()? clock,
    Duration retentionInterval = const Duration(minutes: 1),
  }) : _metrics = metrics,
       _concurrencyLimit = concurrencyLimit,
       _keyStore = keyStore,
       _freeBytes = freeBytes,
       _clock = clock ?? DateTime.now,
       _retentionInterval = retentionInterval;

  final String path;
  final IActionIoMetrics? _metrics;
  final int Function()? _concurrencyLimit;
  final ActionIoSecureKeyStore? _keyStore;
  final Future<int?> Function(String)? _freeBytes;
  final DateTime Function() _clock;
  final Duration _retentionInterval;
  Timer? _retentionTimer;
  Future<Result<int>>? _expiring;
  RandomAccessFile? _owner;
  static final _localOwners = <String>{};
  String? _localOwnerPath;
  ActionIoJournalDatabase? _database;
  DriftActionIoJournal? _journal;
  ActionIoOutputJournal? _output;
  ActionIoJournalRetention? _retention;
  Future<Result<Unit>>? _initializing;
  Future<Result<Unit>>? _closing;
  bool _closed = false;

  bool get isReady => !_closed && _journal != null;
  DriftActionIoJournal get journal => _journal ?? (throw StateError('I/O journal is not ready.'));
  ActionIoOutputJournal get output => _output ?? (throw StateError('I/O journal is not ready.'));

  @override
  Future<Result<ActionIoReadPage>> readLocalOutput({
    required String executionId,
    required int afterSequence,
    required int maxBytes,
  }) async {
    if (!isReady) return Failure(_failure('ACTION_IO_STORAGE_UNAVAILABLE'));
    try {
      final reference = await journal.getSessionReference(executionId);
      if (reference.isError()) return Failure(reference.exceptionOrNull()!);
      return await output.read(
        executionId: executionId,
        clientId: reference.getOrThrow().clientId,
        afterSequence: afterSequence,
        maxBytes: maxBytes,
      );
    } on Object catch (error) {
      return Failure(_failure('ACTION_IO_STORAGE_FAILED', cause: error));
    }
  }

  @override
  Future<Result<List<ActionIoExecutionSnapshot>>> listExecutionSnapshots({
    required int limit,
    ActionIoHistoryCursor? after,
    String? actionId,
    String? idempotencyKey,
    DateTime? requestedAfter,
  }) async {
    if (limit < 1 || limit > IActionIoLocalHistory.maxPageSize) {
      return Failure(_failure('ACTION_IO_INVALID_HISTORY_LIMIT'));
    }
    try {
      if (!isReady) {
        if (!_closed && _initializing == null && !File(path).existsSync()) return const Success([]);
        return Failure(_failure('ACTION_IO_STORAGE_UNAVAILABLE'));
      }
      return await journal.listExecutionSnapshots(
        limit: limit,
        after: after,
        actionId: actionId,
        idempotencyKey: idempotencyKey,
        requestedAfter: requestedAfter,
      );
    } on Object catch (error) {
      return Failure(_failure('ACTION_IO_STORAGE_FAILED', cause: error));
    }
  }

  @override
  Future<Result<bool>> ownsExecution(String executionId) async {
    try {
      if (!isReady) {
        if (!_closed && _initializing == null && !File(path).existsSync()) return const Success(false);
        return Failure(_failure('ACTION_IO_STORAGE_UNAVAILABLE'));
      }
      final rows =
          await (_database!.select(_database!.actionIoSessions)
                ..where((s) => s.executionId.equals(executionId))
                ..limit(1))
              .get();
      return Success(rows.isNotEmpty);
    } on Object catch (error) {
      return Failure(_failure('ACTION_IO_STORAGE_FAILED', cause: error));
    }
  }

  /// Disabled installations create no journal/key. Existing evidence is recovered
  /// even when the opt-in was removed, without enabling new process execution.
  Future<Result<Unit>> prepare({required bool enabled}) async {
    if (_closed) return Failure(_failure('ACTION_IO_RUNTIME_CLOSED'));
    try {
      if (!enabled && !File(path).existsSync()) return const Success(unit);
      return await initialize();
    } on FileSystemException catch (error) {
      return Failure(_failure('ACTION_IO_STORAGE_FAILED', cause: error));
    }
  }

  Future<Result<Unit>> initialize() {
    if (_closed) return Future.value(Failure(_failure('ACTION_IO_RUNTIME_CLOSED')));
    return _initializing ??= _open();
  }

  Future<Result<Unit>> _open() async {
    try {
      if (_retentionInterval <= Duration.zero) throw _failure('ACTION_IO_INVALID_RETENTION_INTERVAL');
      // Nonblocking OS lock. Keep its pathname stable after release; deleting it
      // could let another process lock a different inode for the same journal.
      final lockFile = File('$path.owner.lock');
      // POSIX record locks alone do not exclude a second runtime in this isolate.
      final lockPath = File.fromUri(lockFile.absolute.uri.normalizePath()).path;
      if (!_localOwners.add(lockPath)) throw _failure('ACTION_IO_STORAGE_FAILED');
      _localOwnerPath = lockPath;
      _owner = await lockFile.open(mode: FileMode.append);
      await _owner!.lock();
      final database = ActionIoJournalDatabase(NativeDatabase.createInBackground(File(path)));
      _database = database;
      final existing = await (database.select(database.actionIoSessions)..limit(1)).get();
      final cipher =
          (await (_keyStore ??
                      ActionIoSecureKeyStore(
                        lockPath: '$path.key.lock',
                      ))
                  .load(journalIsEmpty: existing.isEmpty))
              .getOrThrow();
      final mismatchedKey =
          await (database.select(database.actionIoPayloads)
                ..where((p) => p.keyId.equals(cipher.keyId).not())
                ..limit(1))
              .get();
      if (mismatchedKey.isNotEmpty) throw _failure('ACTION_IO_KEY_UNAVAILABLE');
      final physical = ActionIoPhysicalBudget(
        path,
        freeBytes: _freeBytes,
        retainedPayloadBytes: () => readActionIoPayloadBytes(database),
      );
      final journal = DriftActionIoJournal(
        database,
        cipher,
        metrics: _metrics,
        concurrencyLimit: _concurrencyLimit,
        physicalCapacity: physical.checkAdmission,
      );
      (await journal.reconcileInterrupted()).getOrThrow();
      if (_closed) throw _failure('ACTION_IO_RUNTIME_CLOSED');
      _output = ActionIoOutputJournal(database, cipher, physicalCapacity: physical.checkAdmission, metrics: _metrics);
      _retention = ActionIoJournalRetention(database);
      (await _retention!.expire(_clock())).getOrThrow();
      if (_closed) throw _failure('ACTION_IO_RUNTIME_CLOSED');
      _journal = journal;
      _scheduleRetention();
      return const Success(unit);
    } on Object catch (error) {
      final cleanup = await _dispose();
      if (error is ActionFailure) {
        if (cleanup.isSuccess()) return Failure(error);
        return Failure(
          ActionRuntimeFailure.withContext(
            message: error.message,
            code: error.code,
            cause: error,
            context: {...error.context, 'cleanup_failed': true},
          ),
        );
      }
      return Failure(
        _failure(
          'ACTION_IO_STORAGE_FAILED',
          cause: error,
          cleanupFailed: cleanup.isError(),
        ),
      );
    }
  }

  Future<Result<int>> expire(DateTime now) async {
    final retention = _retention;
    if (!isReady || retention == null) return Failure(_failure('ACTION_IO_RUNTIME_CLOSED'));
    return _expiring ??= retention.expire(now).whenComplete(() => _expiring = null);
  }

  void _scheduleRetention() {
    if (!isReady) return;
    _retentionTimer = Timer(_retentionInterval, () => unawaited(_maintainRetention()));
  }

  Future<void> _maintainRetention() async {
    final result = await expire(_clock());
    final error = result.exceptionOrNull();
    if (error is ActionFailure) error.log();
    _scheduleRetention();
  }

  Future<Result<Unit>> close() {
    _closed = true;
    _retentionTimer?.cancel();
    _retentionTimer = null;
    _journal = null;
    _output = null;
    _retention = null;
    return _closing ??= _close();
  }

  Future<Result<Unit>> _close() async {
    await _initializing;
    await _expiring;
    return _dispose();
  }

  Future<Result<Unit>> _dispose() async {
    _journal = null;
    _output = null;
    _retention = null;
    final database = _database;
    final owner = _owner;
    try {
      // Never release ownership if database shutdown is uncertain.
      await database?.close();
      _database = null;
      await owner?.close();
      _owner = null;
      if (_localOwnerPath case final lockPath?) _localOwners.remove(lockPath);
      _localOwnerPath = null;
      return const Success(unit);
    } on Object catch (error) {
      return Failure(_failure('ACTION_IO_STORAGE_FAILED', cause: error));
    }
  }

  ActionRuntimeFailure _failure(String code, {Object? cause, bool cleanupFailed = false}) =>
      ActionRuntimeFailure.withContext(
        message: 'The I/O journal is unavailable. Check its ownership, storage and original encryption key.',
        code: code,
        context: {
          'retryable': false,
          if (cause != null) 'cause_type': cause.runtimeType.toString(),
          if (cleanupFailed) 'cleanup_failed': true,
        },
      );
}
