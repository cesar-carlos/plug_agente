import 'package:plug_agente/application/services/config_service.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:result_dart/result_dart.dart';

class SaveAgentConfig {
  SaveAgentConfig(this._repository, this._service);
  final IAgentConfigRepository _repository;
  final ConfigService _service;

  Future<Result<Config>> call(Config config) async {
    final validationResult = await _service.validateConfig(config);

    return validationResult.fold(
      (isValid) async {
        if (!isValid) {
          return Failure(domain.ValidationFailure('Invalid configuration'));
        }

        return _repository.save(config);
      },
      (failure) {
        return Failure(failure);
      },
    );
  }
}
