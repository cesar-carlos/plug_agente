import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/domain/repositories/i_agent_action_portable_codec.dart';
import 'package:plug_agente/infrastructure/repositories/agent_action_drift_mapper.dart';

class AgentActionPortableCodec implements IAgentActionPortableCodec {
  const AgentActionPortableCodec([AgentActionDriftMapper? mapper]) : _mapper = mapper ?? const AgentActionDriftMapper();

  final AgentActionDriftMapper _mapper;

  @override
  Map<String, Object?> definitionToPortableJson(AgentActionDefinition definition) {
    return _mapper.definitionToPortableJson(definition);
  }

  @override
  Map<String, Object?> triggerToPortableJson(AgentActionTrigger trigger) {
    return _mapper.triggerToPortableJson(trigger);
  }

  @override
  AgentActionDefinition definitionFromPortableJson(Map<String, Object?> json) {
    return _mapper.definitionFromPortableJson(json);
  }

  @override
  AgentActionTrigger triggerFromPortableJson(Map<String, Object?> json) {
    return _mapper.triggerFromPortableJson(json);
  }
}
