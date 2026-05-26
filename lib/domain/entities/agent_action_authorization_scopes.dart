/// OAuth-style scope identifiers for remote `agent.action.*` authorization.
///
/// Used by `ClientTokenPolicyAgentActionAuthorization` to evaluate hub-issued
/// client token policies. The matching advertised scope strings in
/// `AgentActionRpcConstants` (core layer) must stay in sync with these constants.
abstract final class AgentActionAuthorizationScopes {
  static const String run = 'agent_actions.run';
  static const String validateRun = 'agent_actions.validate_run';
  static const String cancel = 'agent_actions.cancel';
  static const String readExecution = 'agent_actions.read_execution';

  /// Wildcard scope that grants all `agent.action.*` RPCs.
  static const String wildcard = 'agent_actions.*';
}
