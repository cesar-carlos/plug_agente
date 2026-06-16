import 'package:plug_agente/application/rpc/sql_streaming_connection_string_cache.dart';
import 'package:plug_agente/application/services/active_config_metadata_cache.dart';
import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:plug_agente/domain/repositories/i_odbc_circuit_breaker_reset.dart';
import 'package:result_dart/result_dart.dart';

class SaveAgentConfig {
  SaveAgentConfig(
    this._repository,
    this._service, {
    IOdbcCircuitBreakerReset? circuitBreakerReset,
    IOdbcCircuitBreakerReset? Function()? circuitBreakerResetProvider,
    ActiveConfigMetadataCache? metadataCache,
    SqlStreamingConnectionStringCache? streamingConnectionStringCache,
  }) : _circuitBreakerReset = circuitBreakerReset,
       _circuitBreakerResetProvider = circuitBreakerResetProvider,
       _metadataCache = metadataCache,
       _streamingConnectionStringCache = streamingConnectionStringCache;

  final IAgentConfigRepository _repository;
  final ConfigService _service;
  final IOdbcCircuitBreakerReset? _circuitBreakerReset;
  final IOdbcCircuitBreakerReset? Function()? _circuitBreakerResetProvider;
  final ActiveConfigMetadataCache? _metadataCache;
  final SqlStreamingConnectionStringCache? _streamingConnectionStringCache;

  IOdbcCircuitBreakerReset? get _resolvedCircuitBreakerReset =>
      _circuitBreakerReset ?? _circuitBreakerResetProvider?.call();

  Future<Result<Config>> call(Config config) async {
    final validationResult = await _service.validateConfig(
      config,
      forPersistence: true,
    );

    return validationResult.fold(
      (_) async {
        final saveResult = await _repository.save(config);
        return saveResult.fold(
          (savedConfig) {
            _metadataCache?.invalidate();
            _streamingConnectionStringCache?.invalidate();
            _resolvedCircuitBreakerReset?.resetForConfig(savedConfig);
            return Success(savedConfig);
          },
          Failure.new,
        );
      },
      Failure.new,
    );
  }
}
