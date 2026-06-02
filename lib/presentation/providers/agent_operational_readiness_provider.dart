import 'package:flutter/foundation.dart';
import 'package:plug_agente/application/actions/agent_action_trigger_scheduler.dart';
import 'package:plug_agente/application/services/agent_operational_readiness_assembler.dart';
import 'package:plug_agente/application/services/agent_operational_readiness_snapshot.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_phase.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';

class AgentOperationalReadinessProvider extends ChangeNotifier {
  AgentOperationalReadinessProvider({
    AgentOperationalReadinessAssembler? assembler,
    AgentActionTriggerScheduler? triggerScheduler,
  }) : _assembler = assembler ?? const AgentOperationalReadinessAssembler(),
       _triggerScheduler = triggerScheduler;

  final AgentOperationalReadinessAssembler _assembler;
  final AgentActionTriggerScheduler? _triggerScheduler;

  ConnectionProvider? _connectionProvider;
  ClientTokenProvider? _clientTokenProvider;

  AgentOperationalReadinessSnapshot _snapshot = const AgentOperationalReadinessSnapshot(
    hubConnected: false,
    hubPhase: HubConnectionPhase.disconnected,
    activeClientTokenCount: 0,
  );

  AgentOperationalReadinessSnapshot get snapshot => _snapshot;

  void bind({
    required ConnectionProvider connectionProvider,
    required ClientTokenProvider clientTokenProvider,
  }) {
    if (!identical(_connectionProvider, connectionProvider)) {
      _connectionProvider?.removeListener(_refresh);
      _connectionProvider = connectionProvider;
      _connectionProvider?.addListener(_refresh);
    }

    if (!identical(_clientTokenProvider, clientTokenProvider)) {
      _clientTokenProvider?.removeListener(_refresh);
      _clientTokenProvider = clientTokenProvider;
      _clientTokenProvider?.addListener(_refresh);
    }

    _refresh();
  }

  @override
  void dispose() {
    _connectionProvider?.removeListener(_refresh);
    _clientTokenProvider?.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    final connection = _connectionProvider;
    final clientTokens = _clientTokenProvider;
    if (connection == null || clientTokens == null) {
      return;
    }

    _snapshot = _assembler.assemble(
      hubPhase: _mapHubPhase(connection.status),
      hubConnected: connection.isConnected,
      clientTokens: clientTokens.tokens,
      schedulerIssueReason: _triggerScheduler?.lastStartIssueReason,
    );
    notifyListeners();
  }

  HubConnectionPhase _mapHubPhase(ConnectionStatus status) {
    return switch (status) {
      ConnectionStatus.connected => HubConnectionPhase.connected,
      ConnectionStatus.connecting || ConnectionStatus.negotiating => HubConnectionPhase.connecting,
      ConnectionStatus.reconnecting => HubConnectionPhase.reconnecting,
      ConnectionStatus.error => HubConnectionPhase.error,
      ConnectionStatus.disconnected => HubConnectionPhase.disconnected,
    };
  }
}
