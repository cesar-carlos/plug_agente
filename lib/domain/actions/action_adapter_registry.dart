import 'package:plug_agente/core/constants/agent_action_resolution_constants.dart';
import 'package:plug_agente/domain/actions/action_adapter.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:result_dart/result_dart.dart';

class AgentActionAdapterRegistry {
  AgentActionAdapterRegistry(Iterable<AgentActionAdapter> adapters) : _adaptersByType = _buildRegistry(adapters);

  final Map<AgentActionType, AgentActionAdapter> _adaptersByType;

  List<AgentActionType> get supportedTypes => List<AgentActionType>.unmodifiable(_adaptersByType.keys);

  Result<AgentActionAdapter> resolve(AgentActionType type) {
    final adapter = _adaptersByType[type];
    if (adapter == null) {
      return Failure(
        ActionValidationFailure.withContext(
          message: 'Action type "${type.name}" is not supported by this agent.',
          context: {
            'action_type': type.name,
            'reason': AgentActionResolutionConstants.unsupportedActionTypeReason,
            'user_message': 'Tipo de acao nao suportado por este agente: ${type.name}.',
          },
        ),
      );
    }

    return Success(adapter);
  }

  static Map<AgentActionType, AgentActionAdapter> _buildRegistry(
    Iterable<AgentActionAdapter> adapters,
  ) {
    final byType = <AgentActionType, AgentActionAdapter>{};
    for (final adapter in adapters) {
      final existing = byType[adapter.type];
      if (existing != null) {
        throw StateError(
          'Duplicate action adapter for "${adapter.type.name}": '
          '${existing.runtimeType} and ${adapter.runtimeType}.',
        );
      }
      byType[adapter.type] = adapter;
    }

    return Map<AgentActionType, AgentActionAdapter>.unmodifiable(byType);
  }
}
