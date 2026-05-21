import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_repository.dart';
import 'package:result_dart/result_dart.dart';

class ListAgentActionDefinitions {
  const ListAgentActionDefinitions(this._repository);

  final IAgentActionRepository _repository;

  Future<Result<List<AgentActionDefinition>>> call() {
    return _repository.listDefinitions();
  }
}
