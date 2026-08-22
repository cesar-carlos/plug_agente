import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_actions_select_builder.dart';

void main() {
  testWidgets('rebuilds only when the selector token changes', (tester) async {
    final notifier = _CountingNotifier();
    var builds = 0;

    await tester.pumpWidget(
      FluentApp(
        home: AgentActionsSelectBuilder(
          listenable: notifier,
          selector: () => notifier.token,
          builder: (context) {
            builds += 1;
            return Text('token-${notifier.token}');
          },
        ),
      ),
    );

    expect(builds, 1);
    expect(find.text('token-0'), findsOneWidget);

    notifier.notifyListeners();
    await tester.pump();

    expect(builds, 1);

    notifier.token = 1;
    notifier.notifyListeners();
    await tester.pump();

    expect(builds, 2);
    expect(find.text('token-1'), findsOneWidget);
  });
}

class _CountingNotifier extends ChangeNotifier {
  int token = 0;
}
