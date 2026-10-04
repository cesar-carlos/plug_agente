import 'dart:async';

import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

enum MaintenanceDecision { ready, deferred }

/// Reversible admission freeze. Every callback must report actual resource
/// state, including native quarantines, rather than just queue length.
class UpdateMaintenanceCoordinator {
  UpdateMaintenanceCoordinator({
    required this.freezeAdmission,
    required this.restoreAdmission,
    required this.isSafelyIdle,
    required this.applyExitPolicies,
    required this.flushAndCloseLocalData,
    DateTime Function()? clock,
    Future<void> Function(Duration)? wait,
  }) : _clock = clock ?? DateTime.now,
       _wait = wait ?? Future<void>.delayed;

  final void Function() freezeAdmission;
  final void Function() restoreAdmission;
  final bool Function() isSafelyIdle;
  final Future<Result<void>> Function(String operationId) applyExitPolicies;
  final Future<Result<void>> Function() flushAndCloseLocalData;
  final DateTime Function() _clock;
  final Future<void> Function(Duration) _wait;
  final Map<String, Future<Result<void>>> _exitPolicies = {};
  Future<Result<MaintenanceDecision>>? _preparation;
  String? _operationId;
  DateTime? retryAfter;
  bool _sealed = false;
  bool _cancelRequested = false;
  bool _frozen = false;
  bool _effectsStarted = false;

  Future<Result<MaintenanceDecision>> prepare(String operationId) {
    if (_preparation != null) {
      if (_operationId == operationId) return _preparation!;
      return Future.value(
        Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Outra atualização está em preparação.',
            context: const {'reason': 'maintenance_in_progress'},
          ),
        ),
      );
    }
    if (retryAfter case final nextAttempt? when _clock().isBefore(nextAttempt)) {
      return Future.value(const Success(MaintenanceDecision.deferred));
    }
    _operationId = operationId;
    _cancelRequested = false;
    _effectsStarted = false;
    final future = _prepare(operationId);
    _preparation = future;
    return future.whenComplete(() {
      if (!_sealed) {
        _preparation = null;
        _operationId = null;
      }
    });
  }

  Future<Result<MaintenanceDecision>> _prepare(String operationId) async {
    try {
      freezeAdmission();
      _frozen = true;
      final deadline = _clock().add(const Duration(seconds: 60));
      while (!isSafelyIdle()) {
        if (_cancelRequested || !_clock().isBefore(deadline)) {
          retryAfter = _clock().add(const Duration(minutes: 15));
          _restore();
          return const Success(MaintenanceDecision.deferred);
        }
        await _wait(const Duration(milliseconds: 100));
      }
      if (_cancelRequested) {
        _restore();
        return const Success(MaintenanceDecision.deferred);
      }
      // Never evict an attempt whose exit effects could be replayed. A bounded
      // ledger fails closed rather than silently forgetting a prior execution.
      if (!_exitPolicies.containsKey(operationId) && _exitPolicies.length >= 64) {
        _restore();
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'Reinicie o agente antes de preparar outra atualização.',
            context: const {'reason': 'maintenance_attempt_limit'},
          ),
        );
      }
      final remaining = deadline.difference(_clock());
      if (remaining <= Duration.zero) {
        retryAfter = _clock().add(const Duration(minutes: 15));
        _restore();
        return const Success(MaintenanceDecision.deferred);
      }
      Result<void> policies;
      try {
        _effectsStarted = true;
        policies = await _exitPolicies
            .putIfAbsent(operationId, () => applyExitPolicies(operationId))
            .timeout(remaining);
      } on TimeoutException {
        // Future.timeout does not cancel the underlying exit policy. It may
        // still be mutating local/external state, so admission cannot reopen.
        _sealed = true;
        return Failure(
          domain.ConfigurationFailure.withContext(
            message: 'As ações de encerramento ainda não foram confirmadas.',
            context: const {'reason': 'exit_policies_pending', 'outcome_unknown': true},
          ),
        );
      }
      if (policies.isError()) {
        final error = policies.exceptionOrNull()!;
        if ((error is domain.Failure && error.context['outcome_unknown'] == true) || !isSafelyIdle()) {
          _sealed = true;
        } else {
          _restore();
        }
        return Failure(error);
      }
      // Exit policies may have generated work. No cleanup or snapshot until it ends.
      if (_cancelRequested || !isSafelyIdle() || !_clock().isBefore(deadline)) {
        retryAfter = _clock().add(const Duration(minutes: 15));
        _restore();
        return const Success(MaintenanceDecision.deferred);
      }
      _sealed = true;
      final closed = await flushAndCloseLocalData().timeout(deadline.difference(_clock()));
      if (closed.isError()) {
        // Once local data closure began, reopening requires explicit recovery.
        // Do not expose a half-closed application as operational.
        _sealed = true;
        return Failure(closed.exceptionOrNull()!);
      }
      _sealed = true;
      return const Success(MaintenanceDecision.ready);
    } on Object catch (error) {
      if (_effectsStarted) _sealed = true;
      if (!_sealed) _restore();
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Não foi possível preparar a manutenção com segurança.',
          cause: error,
          context: const {'reason': 'maintenance_unconfirmed'},
        ),
      );
    }
  }

  void cancel() {
    if (_sealed) return;
    // Preparation owns restoration. Never resume while a callback is pending,
    // or let a second preparation race the first one's delayed continuation.
    _cancelRequested = true;
    if (_preparation == null) _restore();
  }

  void _restore() {
    if (!_frozen) return;
    _frozen = false;
    restoreAdmission();
  }
}
