import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/queue/sql_execution_kind.dart';
import 'package:plug_agente/application/queue/sql_queue_lane_scheduler.dart';

final class _QueuedItem {
  _QueuedItem(this.sequence, this.kind);

  final int sequence;
  final SqlExecutionKind kind;
}

void main() {
  group('SqlQueueLaneScheduler', () {
    const scheduler = SqlQueueLaneScheduler<_QueuedItem>();
    late SqlQueueLaneSchedulerState state;
    late Map<SqlExecutionKind, Queue<_QueuedItem>> queues;

    setUp(() {
      state = SqlQueueLaneSchedulerState();
      queues = {
        for (final kind in SqlExecutionKind.values) kind: Queue<_QueuedItem>(),
      };
    });

    test('round-robins across lanes while preserving lane FIFO', () {
      queues[SqlExecutionKind.batch]!.add(_QueuedItem(1, SqlExecutionKind.batch));
      queues[SqlExecutionKind.query]!.add(_QueuedItem(2, SqlExecutionKind.query));
      queues[SqlExecutionKind.batch]!.add(_QueuedItem(3, SqlExecutionKind.batch));

      final first = scheduler.takeNextQueuedRequest(
        queues: queues,
        roundRobinState: state,
      );
      final second = scheduler.takeNextQueuedRequest(
        queues: queues,
        roundRobinState: state,
      );
      final third = scheduler.takeNextQueuedRequest(
        queues: queues,
        roundRobinState: state,
      );

      expect(first?.sequence, 2);
      expect(second?.sequence, 1);
      expect(third?.sequence, 3);
    });

    test('skips ineligible lanes without breaking ordering in eligible lanes', () {
      queues[SqlExecutionKind.streaming]!.add(_QueuedItem(10, SqlExecutionKind.streaming));
      queues[SqlExecutionKind.query]!.add(_QueuedItem(11, SqlExecutionKind.query));

      final selected = scheduler.takeNextEligibleRequest(
        queues: queues,
        roundRobinState: state,
        canStartRequest: (request) => request.kind != SqlExecutionKind.streaming,
      );

      expect(selected?.sequence, 11);
      expect(queues[SqlExecutionKind.streaming], hasLength(1));
    });
  });
}
