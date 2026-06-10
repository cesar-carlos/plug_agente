/// Shared ODBC execution deadline helpers.
///
/// Extracted from gateway, query runner, connection manager, and batch
/// executors so timeout budgeting stays consistent across acquire and execute.
class OdbcExecutionDeadline {
  OdbcExecutionDeadline._();

  static DateTime? deadlineFor(Duration? timeout) {
    return timeout == null ? null : DateTime.now().add(timeout);
  }

  static Duration? remainingFromDeadline(DateTime? deadline) {
    if (deadline == null) {
      return null;
    }
    final remaining = deadline.difference(DateTime.now());
    return remaining <= Duration.zero ? Duration.zero : remaining;
  }
}
