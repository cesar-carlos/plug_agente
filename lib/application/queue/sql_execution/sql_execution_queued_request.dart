import 'dart:async';

import 'package:plug_agente/application/queue/sql_execution_kind.dart';
import 'package:plug_agente/domain/entities/cancellation_token.dart';
import 'package:result_dart/result_dart.dart';

class SqlExecutionQueuedRequest<T extends Object> {
  SqlExecutionQueuedRequest({
    required this.task,
    required this.enqueuedAt,
    required this.kind,
    required this.sequence,
    this.requestId,
    this.cooperativeCancellationToken,
    this.slotWeight = 1,
  }) : releasableTask = null;

  SqlExecutionQueuedRequest.releasable({
    required Future<Result<T>> Function(void Function() releaseWorker) task,
    required this.enqueuedAt,
    required this.kind,
    required this.sequence,
    this.requestId,
    this.cooperativeCancellationToken,
    this.slotWeight = 1,
  }) : task = null,
       releasableTask = task;

  final Future<Result<T>> Function()? task;
  final Future<Result<T>> Function(void Function() releaseWorker)? releasableTask;
  final CancellationToken? cooperativeCancellationToken;
  final DateTime enqueuedAt;
  final SqlExecutionKind kind;
  final int sequence;
  final int slotWeight;
  final String? requestId;
  bool hasStarted = false;
  bool isCancelled = false;
  bool workerSlotReleased = false;
  DateTime? startedAt;
  final Completer<void> startedCompleter = Completer<void>();
  final Completer<Result<T>> completer = Completer<Result<T>>();

  void completeFailure(Exception failure) {
    if (!completer.isCompleted) {
      completer.complete(Failure<T, Exception>(failure));
    }
  }
}
