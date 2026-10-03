import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/agent_action_draft.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/editor/agent_action_execution_policies_section.dart';

void main() {
  late AppLocalizations l10n;
  late AgentActionDraft draft;
  setUp(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pt'));
    draft = AgentActionDraft()..executionPolicy.maxRuntimeMinutes.text = '1';
  });
  tearDown(() => draft.dispose());

  Future<void> pumpPolicies(WidgetTester tester, {required bool supportsTermination}) async {
    await tester.binding.setSurfaceSize(const Size(1000, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: StatefulBuilder(
            builder: (context, setState) => SingleChildScrollView(
              child: AgentActionExecutionPoliciesSection(
                l10n: l10n,
                enabled: true,
                elevatedFeatureEnabled: false,
                elevatedRunnerReady: false,
                maxAttempts: 1,
                maxRuntimeMinutesController: draft.executionPolicy.maxRuntimeMinutes,
                stopTimeController: draft.executionPolicy.stopTimeOfDay,
                runtimeInSeconds: draft.runtimeInSeconds,
                supportsProcessTermination: supportsTermination,
                killMainProcessOnTimeout: true,
                allowRemoteRetry: false,
                runElevated: false,
                contextInjectionMode: AgentActionContextInjectionMode.argument,
                pathChangePolicy: AgentActionPathChangePolicy.failIfChanged,
                runtimeParameterSchemaController: draft.executionPolicy.runtimeParameterSchema,
                callbacks: AgentActionExecutionPoliciesCallbacks(
                  onMaxAttemptsChanged: (_) {},
                  onMaxRuntimeMinutesChanged: (_) {},
                  onRuntimeUnitChanged: (seconds) => setState(() => draft.setRuntimeUnit(seconds)),
                  onStopTimeChanged: (_) {},
                  onKillOnTimeoutChanged: (_) {},
                  onAllowRemoteRetryChanged: (_) {},
                  onRunElevatedChanged: (_) {},
                  onContextInjectionModeChanged: (_) {},
                  onPathChangePolicyChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('changing runtime unit preserves duration and exposes the scheduled stop field', (tester) async {
    await pumpPolicies(tester, supportsTermination: true);
    expect(find.text(l10n.agentActionsFormStopTime), findsOneWidget);
    await tester.tap(find.text(l10n.agentActionsFormRuntimeUnitMinutes));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.agentActionsFormRuntimeUnitSeconds).last);
    await tester.pumpAndSettle();
    expect(find.text(l10n.agentActionsFormMaxRuntimeSeconds), findsOneWidget);
    expect(draft.executionPolicy.maxRuntimeMinutes.text, '60');
    expect(draft.timeoutPolicy().maxRuntime, const Duration(minutes: 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('process controls are disabled and their limitation is explained for email and COM', (tester) async {
    await pumpPolicies(tester, supportsTermination: false);
    expect(find.text(l10n.agentActionsProcessTerminationUnavailable), findsOneWidget);
    expect(find.text(l10n.agentActionsFormStopTime), findsNothing);
    final checkbox = tester.widget<Checkbox>(
      find.ancestor(of: find.text(l10n.agentActionsFormKillOnTimeout), matching: find.byType(Checkbox)),
    );
    expect(checkbox.checked, isFalse);
    expect(checkbox.onChanged, isNull);
    expect(tester.takeException(), isNull);
  });
}
