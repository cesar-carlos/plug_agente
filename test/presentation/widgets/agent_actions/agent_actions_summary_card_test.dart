import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/agent_actions_provider.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_summary_card.dart';

class _MockAgentActionsProvider extends Mock implements AgentActionsProvider {}

void main() {
  late AppLocalizations l10n;
  late _MockAgentActionsProvider provider;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  setUp(() {
    provider = _MockAgentActionsProvider();
    when(() => provider.definitions).thenReturn(const []);
    when(() => provider.summaryQueuedCount).thenReturn(1);
    when(() => provider.summaryRunningCount).thenReturn(2);
    when(() => provider.failedCount).thenReturn(3);
    when(() => provider.isMaintenanceMode).thenReturn(false);
    when(() => provider.comObjectHandlersRegisteredCount).thenReturn(null);
  });

  Future<void> pumpCard(WidgetTester tester) async {
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AgentActionsSummaryCard(provider: provider, l10n: l10n),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('should show core execution metrics from provider', (tester) async {
    await pumpCard(tester);

    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryQueued), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryRunning), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryFailed), findsOneWidget);
  });

  testWidgets('should show maintenance metric when maintenance mode is on', (tester) async {
    when(() => provider.isMaintenanceMode).thenReturn(true);

    await pumpCard(tester);

    expect(find.text(l10n.agentActionsSummaryMaintenance), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryMaintenanceActive), findsOneWidget);
  });

  testWidgets('should show com handlers count or none label when diagnostics are wired', (tester) async {
    when(() => provider.comObjectHandlersRegisteredCount).thenReturn(0);

    await pumpCard(tester);

    expect(find.text(l10n.agentActionsSummaryComHandlers), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryComHandlersNone), findsOneWidget);

    when(() => provider.comObjectHandlersRegisteredCount).thenReturn(4);
    await pumpCard(tester);

    expect(find.text('4'), findsOneWidget);
    expect(find.text(l10n.agentActionsSummaryComHandlersNone), findsNothing);
  });
}
