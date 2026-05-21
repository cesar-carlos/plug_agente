/// Stable failure phase values exposed in execution history filters.
abstract final class AgentActionFailurePhaseFilterConstants {
  static const List<String> historyFilterPhases = <String>[
    'execution_preflight',
    'definition_validation',
    'start_process',
    'stdin_setup',
    'process_runtime',
    'process_exit',
    'queue',
    'timeout',
    'authorization',
    'validation',
    'lookup',
    'cancel',
    'platform_check',
    'smtp_send',
    'execution_send',
    'elevated_submit',
    'bootstrap_reconciliation',
  ];
}
