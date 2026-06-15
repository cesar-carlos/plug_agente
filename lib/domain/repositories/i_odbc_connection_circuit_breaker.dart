/// Resets a per-connection-string ODBC circuit breaker.
abstract interface class IOdbcConnectionCircuitBreaker {
  void resetCircuitBreaker(String connectionString);
}
