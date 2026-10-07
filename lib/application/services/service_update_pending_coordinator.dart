import 'dart:async';

import 'package:plug_agente/application/services/i_pending_silent_update_store.dart';
import 'package:plug_agente/application/services/pending_silent_update.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/services/i_privileged_updater.dart';
import 'package:result_dart/result_dart.dart';

enum ServicePendingDecision { none, ready, active, finished, attention }

class ServicePendingResolution {
  const ServicePendingResolution(this.decision, {this.pending, this.status});
  final ServicePendingDecision decision;
  final PendingSilentUpdateService? pending;
  final UpdaterStatus? status;
}

class ServiceUpdatePendingCoordinator {
  ServiceUpdatePendingCoordinator({
    required this.updater,
    required this.store,
    required this.flush,
    required this.clock,
    required this.stagedTtl,
    this.onFinished,
  });
  final IPrivilegedUpdater updater;
  final IPendingSilentUpdateStore store;
  final Future<void> Function() flush;
  final DateTime Function() clock;
  final Duration stagedTtl;
  final Future<void> Function(UpdaterStatus status)? onFinished;
  Future<void> _tail = Future.value();

  Future<bool> isReady(PendingSilentUpdateService pending) async {
    if (pending.requiresNewPreparation ||
        pending.cancelRequested ||
        pending.dispatchAttemptedAt != null ||
        pending.startedAt == null ||
        clock().difference(pending.startedAt!) > stagedTtl) {
      return false;
    }
    final result = await updater.status();
    if (result.isError()) return false;
    final status = result.getOrThrow();
    return status.ownedByCaller &&
        status.operationId == pending.operationId &&
        status.version == pending.version &&
        status.phase == UpdaterPhase.preparing &&
        !status.finalizationPending;
  }

  Future<Result<ServicePendingResolution>> reconcile({bool cancel = false}) {
    final previous = _tail;
    final done = Completer<void>();
    _tail = done.future;
    return (() async {
      await previous;
      try {
        return await _reconcile(cancel: cancel);
      } on Object catch (error) {
        return Failure<ServicePendingResolution, Exception>(
          domain.ConfigurationFailure.withContext(
            message: 'Não foi possível reconciliar a atualização. Tente novamente.',
            cause: error,
            context: const {'reason': 'service_reconciliation_unknown', 'outcome_unknown': true},
          ),
        );
      } finally {
        done.complete();
      }
    })();
  }

  Future<Result<ServicePendingResolution>> _reconcile({required bool cancel}) async {
    final local = await store.read();
    var pending = local is PendingSilentUpdateService ? local : null;
    if (cancel && pending != null && !pending.cancelRequested) {
      pending = pending.copyWith(cancelRequested: true);
      await store.write(pending);
      await flush();
    }
    final result = await updater.status();
    if (result.isError()) return Failure(result.exceptionOrNull()!);
    var status = result.getOrThrow();
    if (pending == null) {
      if (!status.ownedByCaller || status.operationId == null || status.version == null) {
        if (local != null && local is! PendingSilentUpdateService) {
          await store.clear();
          await flush();
        }
        return const Success(ServicePendingResolution(ServicePendingDecision.none));
      }
      if (status.phase == UpdaterPhase.preparing) {
        pending = PendingSilentUpdateService(
          version: status.version!,
          startedAt: clock(),
          operationId: status.operationId!,
          cancelRequested: true,
        );
        await store.write(pending);
        await flush();
      } else if (status.active || status.requiresRecovery || status.finalizationPending) {
        pending = PendingSilentUpdateService(
          version: status.version!,
          startedAt: clock(),
          operationId: status.operationId!,
          dispatchAttemptedAt: clock(),
        );
        await store.write(pending);
        await flush();
      } else {
        if (local != null && local is! PendingSilentUpdateService) {
          await store.clear();
          await flush();
        }
        return const Success(ServicePendingResolution(ServicePendingDecision.none));
      }
    }
    if (!status.ownedByCaller || status.operationId != pending.operationId || status.version != pending.version) {
      return Success(ServicePendingResolution(ServicePendingDecision.attention, pending: pending, status: status));
    }
    final expired =
        pending.requiresNewPreparation ||
        pending.startedAt == null ||
        clock().difference(pending.startedAt!) > stagedTtl;
    if ((cancel || pending.cancelRequested || expired) && status.phase == UpdaterPhase.preparing) {
      pending = pending.copyWith(cancelRequested: true);
      await store.write(pending);
      await flush();
      final cancelled = await updater.cancel(pending.operationId);
      if (cancelled.isError()) return Failure(cancelled.exceptionOrNull()!);
      status = cancelled.getOrThrow();
      if (status.operationId != pending.operationId ||
          !status.ownedByCaller ||
          status.phase != UpdaterPhase.deferred ||
          status.reason != 'cancelled_before_installation') {
        return Success(ServicePendingResolution(ServicePendingDecision.attention, pending: pending, status: status));
      }
    }
    if (status.finalizationPending || status.active || status.requiresRecovery) {
      return Success(
        ServicePendingResolution(
          status.requiresRecovery ? ServicePendingDecision.attention : ServicePendingDecision.active,
          pending: pending,
          status: status,
        ),
      );
    }
    if (status.terminal || status.phase == UpdaterPhase.deferred) {
      await onFinished?.call(status);
      await store.clear();
      await flush();
      return Success(ServicePendingResolution(ServicePendingDecision.finished, pending: pending, status: status));
    }
    return Success(
      ServicePendingResolution(
        status.phase == UpdaterPhase.preparing && !pending.cancelRequested && pending.dispatchAttemptedAt == null
            ? ServicePendingDecision.ready
            : ServicePendingDecision.attention,
        pending: pending,
        status: status,
      ),
    );
  }
}
