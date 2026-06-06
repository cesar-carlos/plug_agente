import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/agent_operational_readiness_assembler.dart';
import 'package:plug_agente/application/services/agent_operational_readiness_snapshot.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/value_objects/hub_connection_phase.dart';
import 'package:plug_agente/presentation/providers/agent_operational_readiness_provider.dart';
import 'package:plug_agente/presentation/providers/client_token_provider.dart';
import 'package:plug_agente/presentation/providers/connection_provider.dart';

class MockConnectionProvider extends Mock implements ConnectionProvider {}

class MockClientTokenProvider extends Mock implements ClientTokenProvider {}

class SpyAgentOperationalReadinessAssembler extends AgentOperationalReadinessAssembler {
  int assembleCallCount = 0;

  @override
  AgentOperationalReadinessSnapshot assemble({
    required HubConnectionPhase hubPhase,
    required bool hubConnected,
    required List<ClientTokenSummary> clientTokens,
    String? schedulerIssueReason,
  }) {
    assembleCallCount++;
    return super.assemble(
      hubPhase: hubPhase,
      hubConnected: hubConnected,
      clientTokens: clientTokens,
      schedulerIssueReason: schedulerIssueReason,
    );
  }
}

void main() {
  late MockConnectionProvider connectionProvider;
  late MockClientTokenProvider clientTokenProvider;
  late SpyAgentOperationalReadinessAssembler assembler;
  late AgentOperationalReadinessProvider readinessProvider;

  final connectionListeners = <VoidCallback>[];
  final clientTokenListeners = <VoidCallback>[];

  setUp(() {
    connectionProvider = MockConnectionProvider();
    clientTokenProvider = MockClientTokenProvider();
    assembler = SpyAgentOperationalReadinessAssembler();
    connectionListeners.clear();
    clientTokenListeners.clear();

    when(() => connectionProvider.status).thenReturn(ConnectionStatus.connected);
    when(() => connectionProvider.isConnected).thenReturn(true);
    when(() => clientTokenProvider.tokens).thenReturn(const <ClientTokenSummary>[]);
    when(() => connectionProvider.addListener(any())).thenAnswer((invocation) {
      connectionListeners.add(invocation.positionalArguments[0] as VoidCallback);
    });
    when(() => connectionProvider.removeListener(any())).thenAnswer((invocation) {
      connectionListeners.remove(invocation.positionalArguments[0] as VoidCallback);
    });
    when(() => clientTokenProvider.addListener(any())).thenAnswer((invocation) {
      clientTokenListeners.add(invocation.positionalArguments[0] as VoidCallback);
    });
    when(() => clientTokenProvider.removeListener(any())).thenAnswer((invocation) {
      clientTokenListeners.remove(invocation.positionalArguments[0] as VoidCallback);
    });

    readinessProvider = AgentOperationalReadinessProvider(assembler: assembler);
  });

  void notifyConnectionListeners() {
    for (final listener in List<VoidCallback>.from(connectionListeners)) {
      listener();
    }
  }

  test('bind does not refresh when proxy rebinds identical providers', () {
    readinessProvider.bind(
      connectionProvider: connectionProvider,
      clientTokenProvider: clientTokenProvider,
    );
    expect(assembler.assembleCallCount, 1);

    readinessProvider.bind(
      connectionProvider: connectionProvider,
      clientTokenProvider: clientTokenProvider,
    );
    expect(assembler.assembleCallCount, 1);
  });

  test('notifyListeners is skipped when assembled snapshot is unchanged', () {
    var listenerCalls = 0;
    readinessProvider.addListener(() {
      listenerCalls++;
    });

    readinessProvider.bind(
      connectionProvider: connectionProvider,
      clientTokenProvider: clientTokenProvider,
    );
    expect(listenerCalls, 1);

    notifyConnectionListeners();
    expect(assembler.assembleCallCount, 2);
    expect(listenerCalls, 1);
  });

  test('notifyListeners runs when assembled snapshot changes', () {
    readinessProvider.bind(
      connectionProvider: connectionProvider,
      clientTokenProvider: clientTokenProvider,
    );

    var listenerCalls = 0;
    readinessProvider.addListener(() {
      listenerCalls++;
    });

    when(() => connectionProvider.status).thenReturn(ConnectionStatus.reconnecting);
    when(() => connectionProvider.isConnected).thenReturn(false);
    notifyConnectionListeners();

    expect(listenerCalls, 1);
    expect(readinessProvider.snapshot.hubPhase, HubConnectionPhase.reconnecting);
    expect(readinessProvider.snapshot.hubConnected, isFalse);
  });
}
