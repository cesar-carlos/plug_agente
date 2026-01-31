import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:result_dart/result_dart.dart';

class LoadAgentConfig {
  LoadAgentConfig(this._repository);
  final IAgentConfigRepository _repository;

  // Returns Result<Config> - NotFoundFailure indicates no config exists
  // The caller should handle NotFoundFailure as "not found" (null)
  Future<Result<Config>> call(String? id) async {
    if (id != null && id.isNotEmpty) {
      return _repository.getById(id);
    } else {
      return _repository.getCurrentConfig();
    }
  }
}
