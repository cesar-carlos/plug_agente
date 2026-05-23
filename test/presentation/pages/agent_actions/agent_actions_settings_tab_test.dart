import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/actions/agent_action_definition_snapshotter.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/domain/actions/actions.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/runtime/windows_version_info.dart';
import 'package:plug_agente/core/settings/agent_action_retention_settings.dart';
import 'package:plug_agente/l10n/app_localizations.dart';

import 'agent_actions_page_test_harness.dart';

void main() {
  late AppLocalizations ptL10n;

  setUpAll(() async {
    ptL10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('should persist retention values when saved', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();
    await openTab(tester, ptL10n.configTabPreferences);

    await tester.enterText(
      agentActionFormTextBox(ptL10n.agentActionsRetentionExecutionHistory),
      '7',
    );
    await tester.enterText(
      agentActionFormTextBox(ptL10n.agentActionsRetentionRemoteAudit),
      '45',
    );
    await tester.enterText(
      agentActionFormTextBox(ptL10n.agentActionsRetentionCapturedOutput),
      '6',
    );

    await tester.tap(find.text(ptL10n.agentActionsRetentionSave));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsRetentionSavedTitle), findsOneWidget);
    expect(harness.retentionSettings.executionRetentionDays, 7);
    expect(harness.retentionSettings.remoteAuditRetentionDays, 45);
    expect(harness.retentionSettings.capturedOutputRetentionHours, 6);
    expect(find.text(ptL10n.agentActionsRetentionPersistedHint), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('should restore environment retention defaults when requested', (tester) async {
    final harness = AgentActionsPageHarness();
    await harness.retentionSettings.save(
      executionDays: 7,
      remoteAuditDays: 45,
      capturedOutputHours: 6,
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();
    await openTab(tester, ptL10n.configTabPreferences);

    expect(find.text(ptL10n.agentActionsRetentionUseEnvDefaults), findsOneWidget);

    await tester.tap(find.text(ptL10n.agentActionsRetentionUseEnvDefaults));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsRetentionClearedTitle), findsOneWidget);
    expect(harness.retentionSettings.hasPersistedOverrides, isFalse);
    expect(
      harness.retentionSettings.executionRetentionDays,
      AgentActionRetentionSettings.defaultExecutionRetentionDays,
    );
    expect(find.text(ptL10n.agentActionsRetentionPersistedHint), findsNothing);

    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('shows preflight expired infobar when last validation is stale', (tester) async {
    final harness = AgentActionsPageHarness();
    harness.repository.definitions['action-1'] = const AgentActionDefinition(
      id: 'action-1',
      name: 'Run command',
      config: CommandLineActionConfig(command: 'dir'),
    );

    await tester.binding.setSurfaceSize(const Size(1600, 2000));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    await harness.provider.load();
    harness.provider.selectAction('action-1');
    final live = harness.provider.selectedDefinition!;
    const snapshotter = AgentActionDefinitionSnapshotter();
    final preflightHash = snapshotter.snapshotHash(
      live.copyWith(state: AgentActionState.needsValidation),
    );
    harness.repository.definitions['action-1'] = live.copyWith(
      lastPreflightSnapshotHash: preflightHash,
      lastPreflightValidatedAt: DateTime.utc(2020),
    );
    await harness.provider.load();
    harness.provider.selectAction('action-1');

    final fromProvider = harness.provider.definitions.single;
    expect(fromProvider.lastPreflightValidatedAt, DateTime.utc(2020));
    expect(harness.provider.isPreflightExpiredForDefinition(fromProvider), isTrue);

    await openSelectedActionDialog(tester);

    expect(find.text(ptL10n.agentActionsPreflightExpiredTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsPreflightExpiredForActive), findsOneWidget);
  });

  testWidgets('preferences tab shows dangerous-command warn card and reflects flag changes', (tester) async {
    final harness = AgentActionsPageHarness();

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();

    await openTab(tester, ptL10n.configTabPreferences);

    expect(find.text(ptL10n.agentActionsPreflightSettingsTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsDangerousCommandWarnModeTitle), findsOneWidget);
    expect(find.text(ptL10n.agentActionsDangerousCommandWarnModeDisabled), findsOneWidget);

    await harness.featureFlags.setEnableAgentActionDangerousCommandWarnMode(true);
    harness.provider.notifyListeners();
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.agentActionsDangerousCommandWarnModeEnabled), findsOneWidget);
  });

  testWidgets('shows runtime support diagnostics card when desktop runtime is degraded', (tester) async {
    final harness = AgentActionsPageHarness(
      runtimeCapabilities: RuntimeCapabilities.degraded(
        reasons: <String>[
          'Windows Server detectado',
          'Versão: 10.0.17763',
        ],
      ),
      runtimeDiagnostics: RuntimeDetectionDiagnostics.detected(
        source: RuntimeDetectionSource.rtlGetVersion,
        versionInfo: const WindowsVersionInfo(
          majorVersion: 10,
          minorVersion: 0,
          buildNumber: 17763,
          isServer: true,
          productName: 'Windows Server 2019',
        ),
      ),
    );

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    await tester.pumpWidget(harness.buildWidget());
    await tester.pumpAndSettle();
    await openTab(tester, ptL10n.configTabPreferences);

    expect(find.text('Runtime Detection'), findsOneWidget);
    expect(find.textContaining('runtime_mode: degraded', findRichText: true), findsWidgets);
    expect(find.textContaining('product_name: Windows Server 2019', findRichText: true), findsWidgets);
  });

}
