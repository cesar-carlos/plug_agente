/// Resets a per-connection-string ODBC circuit breaker.
abstract interface class IOdbcConnectionCircuitBreaker {
  void resetCircuitBreaker(String connectionString);

  /// Drops every cached breaker after native worker recovery or full disconnect.
  void clearAllCircuitBreakers();
}
