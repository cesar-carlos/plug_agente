/// A log-safe subprocess failure cause.
///
/// OS exceptions may embed the complete command line, including resolved
/// secrets. Keep the raw exception out of the domain failure so every sink and
/// `Failure.toString()` remain safe by construction.
class AgentActionProcessFailureCause implements Exception {
  const AgentActionProcessFailureCause({
    required this.phase,
    required this.exceptionType,
  });

  factory AgentActionProcessFailureCause.fromException({
    required String phase,
    required Object error,
  }) {
    return AgentActionProcessFailureCause(
      phase: phase,
      exceptionType: error.runtimeType.toString(),
    );
  }

  final String phase;
  final String exceptionType;

  @override
  String toString() => 'Process failure during $phase ($exceptionType).';
}
