import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';

import 'agent_actions_page_test_harness.dart';

void main() {
  testWidgets('long-running action keeps status and stop control without scheduling continuous frames', (tester) async {
    final harness = AgentActionsPageHarness(useExecutionQueue: false);
    harness.repository.definitions['long-action'] = const AgentActionDefinition(
      id: 'long-action',
      name: 'Long-running command',
      state: AgentActionState.active,
      config: CommandLineActionConfig(command: 'echo fixture'),
    );
    harness.repository.executions['long-execution'] = AgentActionExecution(
      id: 'long-execution',
      actionId: 'long-action',
      actionType: AgentActionType.commandLine,
      status: AgentActionExecutionStatus.running,
      requestedAt: DateTime.now(),
      source: AgentActionRequestSource.localUi,
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      harness.provider.dispose();
      await getIt.reset();
      await tester.binding.setSurfaceSize(null);
    });
    await harness.pumpPage(tester, size: const Size(1400, 900));
    for (var frame = 0; frame < 10; frame++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(harness.provider.isDefinitionRunning('long-action'), isTrue);
    expect(find.text('Long-running command'), findsWidgets);
    final stop = find.byKey(const ValueKey<String>('agent_action_definition_stop_long-action'));
    expect(stop, findsOneWidget);
    expect(tester.widget<IconButton>(stop).onPressed, isNotNull);
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(find.byTooltip('Executando'), findsOneWidget);
    await tester.pump(const Duration(minutes: 5));
    expect(harness.provider.isDefinitionRunning('long-action'), isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
