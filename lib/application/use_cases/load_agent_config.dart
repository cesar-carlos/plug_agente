import 'package:result_dart/result_dart.dart';

import '../../domain/entities/config.dart';
import '../../domain/repositories/i_agent_config_repository.dart';

class LoadAgentConfig {
  final IAgentConfigRepository _repository;

  LoadAgentConfig(this._repository);

  // Returns Result<Config> - NotFoundFailure indicates no config exists
  // The caller should handle NotFoundFailure as "not found" (null)
  Future<Result<Config>> call(String? id) async {
    if (id != null && id.isNotEmpty) {
      return await _repository.getById(id);
    } else {
      return await _repository.getCurrentConfig();
    }
  }
}
