import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_remote_access_panel.dart';
import 'package:provider/provider.dart';
import '../../pages/agent_actions/agent_actions_page_test_harness.dart';

void main() {
  testWidgets('options are reachable from System Actions preferences', (tester) async {
    final harness = AgentActionsPageHarness();
    addTearDown(harness.provider.dispose);
    final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
    await harness.pumpPage(tester, size: const Size(1100, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await openTab(tester, l10n.configTabPreferences);
    await tester.ensureVisible(find.text(l10n.remoteAccessTitle));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.remoteAccessTitle));
    await tester.pumpAndSettle();
    expect(find.text(l10n.remoteAccessEnabled), findsOneWidget);
    expect(find.text(l10n.remoteAccessIo), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('remote access toggles, restart guidance and maintenance in $mode', (tester) async {
      final harness = AgentActionsPageHarness();
      addTearDown(harness.provider.dispose);
      await tester.binding.setSurfaceSize(const Size(600, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        FluentApp(
          themeMode: mode,
          locale: const Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChangeNotifierProvider<AgentActionsProvider>.value(
            value: harness.provider,
            child: const ScaffoldPage(content: SingleChildScrollView(child: AgentActionsRemoteAccessPanel())),
          ),
        ),
      );
      await tester.tap(find.text('Ações remotas e entrada/saída'));
      await tester.pumpAndSettle();
      final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
      expect(find.text(l10n.remoteCheckActions), findsOneWidget);
      expect(tester.widget<ToggleSwitch>(find.byType(ToggleSwitch).at(1)).onChanged, isNull);
      await tester.tap(find.byType(ToggleSwitch).first);
      await tester.pumpAndSettle();
      expect(harness.featureFlags.enableRemoteAgentActions, isTrue);
      expect(find.text(l10n.remoteCheckIo), findsOneWidget);
      await tester.tap(find.byType(ToggleSwitch).at(1));
      await tester.pumpAndSettle();
      expect(harness.featureFlags.enableActionIo, isTrue);
      expect(find.text(l10n.remoteCheckApproval), findsOneWidget);
      expect(find.textContaining('saia do agente pela bandeja'), findsOneWidget);
      expect(harness.featureFlags.enableRemoteAdHocAgentActions, isFalse);
      await tester.tap(find.byType(ToggleSwitch).at(2));
      await tester.pumpAndSettle();
      expect(harness.featureFlags.enableRemoteAdHocAgentActions, isTrue);
      await tester.tap(find.byType(ToggleSwitch).first);
      await tester.pumpAndSettle();
      expect(harness.featureFlags.enableRemoteAgentActions, isFalse);
      await tester.tap(find.byType(ToggleSwitch).at(2));
      await tester.pumpAndSettle();
      expect(harness.featureFlags.enableRemoteAdHocAgentActions, isFalse);
      expect(harness.featureFlags.enableRemoteAgentActions, isFalse);
      await tester.tap(find.byType(ToggleSwitch).at(1));
      await tester.pumpAndSettle();
      expect(harness.featureFlags.enableRemoteAgentActions, isFalse);
      expect(harness.featureFlags.enableActionIo, isFalse);
      await harness.provider.setMaintenanceMode(enabled: true);
      await tester.pumpAndSettle();
      for (final toggle in tester.widgetList<ToggleSwitch>(find.byType(ToggleSwitch))) {
        expect(toggle.onChanged, isNull);
      }
      expect(tester.takeException(), isNull);
    });
  }
}
