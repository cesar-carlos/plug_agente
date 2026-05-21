import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';

void main() {
  testWidgets('confirmEnableElevatedAgentAction returns false when cancelled', (tester) async {
    bool? confirmed;

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: Builder(
            builder: (BuildContext context) {
              return FilledButton(
                onPressed: () async {
                  confirmed = await confirmEnableElevatedAgentAction(
                    context: context,
                    l10n: AppLocalizations.of(context)!,
                  );
                },
                child: const Text('Open elevated confirm'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open elevated confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Enable elevated execution?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(confirmed, isFalse);
  });

  testWidgets('confirmEnableElevatedAgentAction returns true when confirmed', (tester) async {
    bool? confirmed;

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: Builder(
            builder: (BuildContext context) {
              return FilledButton(
                onPressed: () async {
                  confirmed = await confirmEnableElevatedAgentAction(
                    context: context,
                    l10n: AppLocalizations.of(context)!,
                  );
                },
                child: const Text('Open elevated confirm'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open elevated confirm'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Enable elevated'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });
}
