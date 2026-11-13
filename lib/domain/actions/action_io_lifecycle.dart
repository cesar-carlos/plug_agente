/// Local support metadata. Never stores commands, input, output or credentials.
enum ActionIoMilestone {
  queued,
  queueReleased,
  processCreated,
  processResumed,
  inputWritten,
  inputClosed,
  timeoutRequested,
  processExited,
  captureDrained,
  cleanupConfirmed,
}

final class ActionQueueBlocker {
  const ActionQueueBlocker({required this.executionId, required this.elapsedMs});
  factory ActionQueueBlocker.fromJson(Map<String, dynamic> json) => ActionQueueBlocker(
    executionId: json['execution_id'] as String,
    elapsedMs: json['elapsed_ms'] as int,
  );
  final String executionId;
  final int elapsedMs;

  Map<String, Object> toJson() => {'execution_id': executionId, 'elapsed_ms': elapsedMs};
}

final class ActionIoLifecycle {
  const ActionIoLifecycle({this.times = const {}, this.pid, this.blockers = const []});
  factory ActionIoLifecycle.fromJson(Map<String, dynamic> json) => ActionIoLifecycle(
    times: {
      for (final entry in (json['times'] as Map<String, dynamic>? ?? {}).entries)
        ActionIoMilestone.values.byName(entry.key): DateTime.parse(entry.value as String),
    },
    pid: json['pid'] as int?,
    blockers: [
      for (final value in json['blocking_executions'] as List? ?? [])
        ActionQueueBlocker.fromJson(value as Map<String, dynamic>),
    ],
  );

  final Map<ActionIoMilestone, DateTime> times;
  final int? pid;

  /// Occupants observed when queue wait expired, not a live process inventory.
  final List<ActionQueueBlocker> blockers;

  Map<String, Object?> toJson() => {
    'times': {for (final entry in times.entries) entry.key.name: entry.value.toUtc().toIso8601String()},
    if (pid != null) 'pid': pid,
    'blocking_executions': blockers.map((value) => value.toJson()).toList(),
  };

  ActionIoLifecycle record(ActionIoMilestone milestone, DateTime at, {int? processId}) => ActionIoLifecycle(
    times: {...times, milestone: times[milestone] ?? at},
    pid: pid ?? processId,
    blockers: blockers,
  );
}
