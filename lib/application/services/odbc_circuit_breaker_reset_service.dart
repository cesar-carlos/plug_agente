import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_config_connection_string_source.dart';
import 'package:plug_agente/domain/repositories/i_odbc_circuit_breaker_reset.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_circuit_breaker.dart';

class OdbcCircuitBreakerResetService implements IOdbcCircuitBreakerReset {
  OdbcCircuitBreakerResetService(
    this._connectionStringSource,
    this._databaseGateway,
    this._streamingGateway,
  );

  final IConfigConnectionStringSource _connectionStringSource;
  final IOdbcConnectionCircuitBreaker _databaseGateway;
  final IOdbcConnectionCircuitBreaker _streamingGateway;

  @override
  void resetForConfig(Config config) {
    for (final connectionString in _connectionStringsForConfig(config)) {
      _databaseGateway.resetCircuitBreaker(connectionString);
      _streamingGateway.resetCircuitBreaker(connectionString);
    }
  }

  Iterable<String> _connectionStringsForConfig(Config config) {
    final runtime = _connectionStringSource.generateConnectionString(config).trim();
    final persisted = _connectionStringSource.generateConnectionStringForPersistence(config).trim();
    if (runtime.isEmpty && persisted.isEmpty) {
      return const [];
    }
    if (runtime.isEmpty) {
      return [persisted];
    }
    if (persisted.isEmpty || persisted == runtime) {
      return [runtime];
    }
    return [runtime, persisted];
  }
}
