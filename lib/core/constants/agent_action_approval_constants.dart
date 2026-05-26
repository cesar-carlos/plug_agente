/// Origin identifiers for `AgentActionDefinition.approvedBy`.
///
/// Used when the local UI approves a definition for activation; stored in the
/// definition entity and compared in use cases and tests.
abstract final class AgentActionApprovalConstants {
  /// `approvedBy` value set when the definition is approved through the local
  /// desktop UI (editor/settings tab, not a remote approval flow).
  static const String localUiApprover = 'local-ui';
}
