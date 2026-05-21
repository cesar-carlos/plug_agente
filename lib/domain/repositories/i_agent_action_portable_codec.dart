import 'package:plug_agente/domain/actions/actions.dart';

/// Converts agent action definitions and triggers to portable JSON maps (Drift-shaped).
abstract class IAgentActionPortableCodec {
  Map<String, Object?> definitionToPortableJson(AgentActionDefinition definition);

  Map<String, Object?> triggerToPortableJson(AgentActionTrigger trigger);

  AgentActionDefinition definitionFromPortableJson(Map<String, Object?> json);

  AgentActionTrigger triggerFromPortableJson(Map<String, Object?> json);
}
