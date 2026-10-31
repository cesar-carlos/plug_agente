import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_io_execution_status.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_io_status_panel.dart';

void main() {
  for (final locale in ['en', 'pt']) {
    for (final brightness in Brightness.values) {
      testWidgets('separates I/O states in $locale with $brightness during resize', (tester) async {
        tester.view.physicalSize = const Size(320, 600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          FluentApp(
            theme: FluentThemeData(brightness: brightness),
            locale: Locale(locale),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const ScaffoldPage(
              content: AgentActionIoStatusPanel(
                status: ActionIoExecutionStatus(
                  processState: 'finished',
                  stdinState: 'unknown',
                  captureState: 'incomplete',
                  outputExpired: true,
                  admittedInputBytes: 7,
                  confirmedInputBytes: 3,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining(locale == 'en' ? 'Input admitted: 7 bytes' : 'Entrada admitida: 7 bytes'), findsOneWidget);
        expect(find.textContaining(locale == 'en' ? 'Confirmed writes to stdin: 3 bytes' : 'Escrita confirmada em stdin: 3 bytes'), findsOneWidget);
        expect(find.text(locale == 'en' ? 'Process: Finished' : 'Processo: Finalizado'), findsOneWidget);
        expect(find.text(locale == 'en' ? 'Input: Unknown' : 'Entrada: Desconhecida'), findsOneWidget);
        expect(find.text(locale == 'en' ? 'Capture: Incomplete' : 'Captura: Incompleta'), findsOneWidget);
        expect(
          find.textContaining(locale == 'en' ? 'Stored output has expired' : 'A saída armazenada expirou'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
        tester.view.physicalSize = const Size(1200, 800);
        await tester.pumpAndSettle();
        expect(find.text(locale == 'en' ? 'Input: Unknown' : 'Entrada: Desconhecida'), findsOneWidget);
        expect(find.text(locale == 'en' ? 'Capture: Incomplete' : 'Captura: Incompleta'), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
