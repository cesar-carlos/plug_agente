import 'dart:collection';

import 'package:plug_agente/application/queue/sql_execution_kind.dart';

/// Selects the next eligible queued SQL request respecting per-lane worker caps.
final class SqlQueueLaneScheduler<T extends Object> {
  const SqlQueueLaneScheduler();

  T? takeNextEligibleRequest({
    required Map<SqlExecutionKind, Queue<T>> queues,
    required bool Function(T request) canStartRequest,
  }) {
    MapEntry<SqlExecutionKind, Queue<T>>? selected;
    for (final entry in queues.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final candidate = entry.value.first;
      if (!canStartRequest(candidate)) {
        continue;
      }
      final current = selected;
      if (current == null || _sequenceOf(candidate) < _sequenceOf(current.value.first)) {
        selected = entry;
      }
    }

    if (selected == null) {
      return null;
    }
    return selected.value.removeFirst();
  }

  T? takeNextQueuedRequest({
    required Map<SqlExecutionKind, Queue<T>> queues,
  }) {
    MapEntry<SqlExecutionKind, Queue<T>>? selected;
    for (final entry in queues.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      final current = selected;
      if (current == null || _sequenceOf(entry.value.first) < _sequenceOf(current.value.first)) {
        selected = entry;
      }
    }

    if (selected == null) {
      return null;
    }
    return selected.value.removeFirst();
  }

  int _sequenceOf(T request) {
    return (request as dynamic).sequence as int;
  }
}
