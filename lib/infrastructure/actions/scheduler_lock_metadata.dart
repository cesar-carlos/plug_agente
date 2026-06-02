class SchedulerLockMetadata {
  const SchedulerLockMetadata({
    this.pid,
    this.acquiredAt,
    this.runtimeInstanceId,
    this.runtimeSessionId,
  });

  final int? pid;
  final DateTime? acquiredAt;
  final String? runtimeInstanceId;
  final String? runtimeSessionId;
}
