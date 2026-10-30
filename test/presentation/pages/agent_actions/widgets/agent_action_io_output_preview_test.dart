import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/actions/action_io.dart';
import 'package:plug_agente/domain/actions/action_io_output.dart';
import 'package:plug_agente/domain/repositories/i_action_io_local_output.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_actions/widgets/agent_action_io_output_preview.dart';
import 'package:result_dart/result_dart.dart';

class _Output implements IActionIoLocalOutput {
  int calls = 0;
  @override
  Future<Result<ActionIoReadPage>> readLocalOutput({
    required String executionId,
    required int afterSequence,
    required int maxBytes,
  }) async {
    calls++;
    return Success(
      ActionIoReadPage(
        events: [
          ActionIoOutputEvent(sequence: calls, stream: ActionIoStream.stdout, offset: calls - 1, bytes: [64 + calls]),
        ],
        nextSequence: calls,
        terminal: false,
        outputComplete: false,
      ),
    );
  }
}

void main() {
  testWidgets('loads only on explicit action and replaces the previous preview page', (tester) async {
    final output = _Output();
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: AgentActionIoOutputPreview(output: output, executionId: 'e'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(output.calls, 0);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('A'), findsOneWidget);
    await tester.tap(find.text('Read next output page'));
    await tester.pumpAndSettle();
    expect(find.text('A'), findsNothing);
    expect(find.text('B'), findsOneWidget);
    expect(output.calls, 2);
    expect(tester.takeException(), isNull);
  });
}
