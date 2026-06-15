import 'package:plug_agente/domain/entities/config.dart';

/// Resets ODBC connection circuit breakers after configuration changes.
abstract interface class IOdbcCircuitBreakerReset {
  void resetForConfig(Config config);
}
