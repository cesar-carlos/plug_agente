import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/actions/agent_action_live_processes.dart';
import 'package:plug_agente/domain/actions/action_failure.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_live_process_panel.dart';
import 'package:result_dart/result_dart.dart';

class _Processes extends Mock implements AgentActionLiveProcesses {}

void main() {
  testWidgets('unchanged CPU display does not rebuild and hidden updates do not sample', (tester) async {
    final processes = _Processes();
    var reads = 0;
    final process = AgentActionLiveProcess(
      executionId: 'run',
      actionId: 'action',
      pid: 42,
      executable: 'script.exe',
      startedAt: DateTime.utc(2026),
      cpuLimitPercent: 0,
      readCpu: () {
        reads++;
        return const Success(Duration.zero);
      },
    );
    when(() => processes.forAction(any())).thenReturn([process]);
    Widget app(bool enabled, String actionId) => FluentApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TickerMode(
        enabled: enabled,
        child: AgentActionLiveProcessPanel(processes: processes, actionId: actionId),
      ),
    );
    await tester.pumpWidget(app(true, 'action'));
    await tester.pump(const Duration(seconds: 1));
    final label = tester.widget(find.byType(SelectableText));
    await tester.pump(const Duration(seconds: 1));
    expect(tester.widget(find.byType(SelectableText)), same(label));
    await tester.pumpWidget(app(false, 'action'));
    final hiddenReads = reads;
    await tester.pumpWidget(app(false, 'another'));
    await tester.pump(const Duration(seconds: 3));
    expect(reads, hiddenReads);
    await tester.pumpWidget(app(true, 'another'));
    expect(reads, greaterThan(hiddenReads));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('shows PID before completion and stops sampling when hidden or disposed', (tester) async {
    final processes = _Processes();
    var reads = 0;
    final process = AgentActionLiveProcess(
      executionId: 'run',
      actionId: 'action',
      pid: 42,
      executable: 'script.exe',
      startedAt: DateTime.utc(2026),
      cpuLimitPercent: 50,
      readCpu: () => Success(Duration(milliseconds: ++reads * 10)),
    );
    when(() => processes.forAction('action')).thenReturn([process]);
    Widget app(bool enabled) => FluentApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TickerMode(
        enabled: enabled,
        child: AgentActionLiveProcessPanel(processes: processes, actionId: 'action'),
      ),
    );
    await tester.pumpWidget(app(true));
    expect(find.textContaining('PID 42'), findsOneWidget);
    final initial = reads;
    await tester.pump(const Duration(seconds: 1));
    expect(reads, initial + 1);
    await tester.pumpWidget(app(false));
    final hidden = reads;
    await tester.pump(const Duration(seconds: 3));
    expect(reads, hidden);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 3));
    expect(reads, hidden);
  });

  testWidgets('failed CPU measurement is unavailable rather than zero', (tester) async {
    final processes = _Processes();
    when(() => processes.forAction('action')).thenReturn([
      AgentActionLiveProcess(
        executionId: 'run',
        actionId: 'action',
        pid: 42,
        executable: 'script.exe',
        startedAt: DateTime.utc(2026),
        cpuLimitPercent: 0,
        readCpu: () => Failure(ActionRuntimeFailure('measurement failed')),
      ),
    ]);
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AgentActionLiveProcessPanel(processes: processes, actionId: 'action'),
      ),
    );
    expect(find.textContaining('Unavailable'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
