import 'package:result_dart/result_dart.dart';

import '../../domain/entities/config.dart';
import '../../domain/repositories/i_agent_config_repository.dart';
import '../services/config_service.dart';
import '../../domain/errors/failures.dart' as domain;

class SaveAgentConfig {
  final IAgentConfigRepository _repository;
  final ConfigService _service;

  SaveAgentConfig(this._repository, this._service);

  Future<Result<Config>> call(Config config) async {
    final validationResult = await _service.validateConfig(config);

    return validationResult.fold(
      (isValid) async {
        if (!isValid) {
          return Failure(domain.ValidationFailure('Invalid configuration'));
        }

        return await _repository.save(config);
      },
      (failure) {
        return Failure(failure);
      },
    );
  }
}
