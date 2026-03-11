/// Constantes para configuração de conexões ODBC.
class ConnectionConstants {
  ConnectionConstants._();

  static const Duration defaultLoginTimeout = Duration(seconds: 30);
  static const Duration defaultQueryTimeout = Duration(seconds: 60);
  static const int defaultMaxResultBufferBytes = 32 * 1024 * 1024;
  static const int defaultInitialResultBufferBytes = 256 * 1024;
  static const int defaultMaxReconnectAttempts = 3;
  static const Duration defaultReconnectBackoff = Duration(seconds: 1);
  static const int defaultPoolSize = 4;
}
