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
  }) : _circuitBreakerReset = circuitBreakerReset,
       _circuitBreakerResetProvider = circuitBreakerResetProvider;

  final IAgentConfigRepository _repository;
  final ConfigService _service;
  final IOdbcCircuitBreakerReset? _circuitBreakerReset;
  final IOdbcCircuitBreakerReset? Function()? _circuitBreakerResetProvider;

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
