import 'package:plug_agente/domain/actions/action_config.dart';
import 'package:plug_agente/domain/actions/action_enums.dart';
import 'package:plug_agente/domain/actions/action_policies.dart';

class AgentActionDefinition {
  const AgentActionDefinition({
    required this.id,
    required this.name,
    required this.config,
    this.description,
    this.state = AgentActionState.needsValidation,
    this.policies = const AgentActionDefinitionPolicies(),
    this.definitionVersion = 1,
    this.definitionSnapshotHash,
    this.lastPreflightSnapshotHash,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String? description;
  final AgentActionConfig config;
  final AgentActionState state;
  final AgentActionDefinitionPolicies policies;
  final int definitionVersion;
  final String? definitionSnapshotHash;
  final String? lastPreflightSnapshotHash;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  AgentActionType get type => config.type;

  bool get canRun => state == AgentActionState.active;

  static const Object _unset = Object();

  AgentActionDefinition copyWith({
    String? id,
    String? name,
    String? description,
    AgentActionConfig? config,
    AgentActionState? state,
    AgentActionDefinitionPolicies? policies,
    int? definitionVersion,
    String? definitionSnapshotHash,
    Object? lastPreflightSnapshotHash = _unset,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return AgentActionDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      config: config ?? this.config,
      state: state ?? this.state,
      policies: policies ?? this.policies,
      definitionVersion: definitionVersion ?? this.definitionVersion,
      definitionSnapshotHash: definitionSnapshotHash ?? this.definitionSnapshotHash,
      lastPreflightSnapshotHash: identical(lastPreflightSnapshotHash, _unset)
          ? this.lastPreflightSnapshotHash
          : lastPreflightSnapshotHash as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
