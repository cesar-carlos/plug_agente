import 'package:plug_agente/domain/actions/action_io.dart';

/// Fixed v1 limits; an incompatible peer cannot silently downgrade fidelity.
abstract final class ActionIoCapability {
  static const methods = <String>[
    'agent.action.sendInput',
    'agent.action.closeInput',
    'agent.action.getInputStatus',
    'agent.action.readIo',
    'agent.action.findExecution',
  ];

  static const advertisement = <String, Object>{
    'version': 1,
    'max_block_bytes': ActionIoLimits.blockBytes,
    'max_read_bytes': ActionIoLimits.pageBytes,
    'max_page_events': ActionIoLimits.pageEvents,
    'max_json_bytes': ActionIoLimits.jsonBytes,
    'max_execution_bytes': ActionIoLimits.executionBytes,
    'max_queued_messages': ActionIoLimits.queuedMessages,
    'max_queued_bytes': ActionIoLimits.queuedBytes,
    'max_execution_messages': ActionIoLimits.executionMessages,
    'max_execution_events': ActionIoLimits.executionEvents,
    'max_wait_ms': 20000,
    'request_timeout_ms': 30000,
    'output_retention_seconds': 86400,
    'deduplication_retention_seconds': 259200,
    'max_readers_per_execution': ActionIoLimits.readersPerExecution,
    'max_readers_per_client': ActionIoLimits.readersPerClient,
    'max_readers_per_connection': ActionIoLimits.readersPerConnection,
    'max_readers_per_agent': ActionIoLimits.readersPerAgent,
    'supports_interactive_input': true,
    'requires_local_credential': true,
    'automatic_replay': false,
  };

  static bool supported(Object? value) =>
      value is Map &&
      value.length == advertisement.length &&
      advertisement.entries.every((e) => value[e.key] == e.value && (e.value is! int || value[e.key] is int));

  static bool negotiated(Map<String, dynamic> extensions) {
    final actions = extensions['agentActions'];
    return actions is Map && supported(actions['io']);
  }

  static Map<String, Object>? negotiate(Object? local, Object? remote) =>
      supported(local) && supported(remote) ? Map.of(advertisement) : null;
}
