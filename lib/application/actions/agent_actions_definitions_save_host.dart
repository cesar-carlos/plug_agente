import 'package:plug_agente/domain/actions/actions.dart';

/// Mutable save-session state owned by the definitions controller
/// and passed into type-specific save handlers.
abstract interface class AgentActionsDefinitionsSaveHost {
  bool get isSaving;
  set isSaving(bool value);

  String? get lastOperationErrorMessage;
  set lastOperationErrorMessage(String? value);

  String? get selectedActionId;
  set selectedActionId(String? value);

  Map<String, String> get sessionPreflightSnapshotHashes;
  Map<String, DateTime> get sessionPreflightValidatedAt;

  void notifyStateChanged();
  AgentActionDefinition? existingDefinition(String? actionId);
}
