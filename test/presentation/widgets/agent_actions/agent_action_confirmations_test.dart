import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/agent_action_confirmations.dart';

typedef _ConfirmFn = Future<bool> Function({
  required BuildContext context,
  required AppLocalizations l10n,
});

Future<bool?> _runConfirmAndTap({
  required WidgetTester tester,
  required _ConfirmFn open,
  required String openLabel,
  required String tapLabel,
}) async {
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
                confirmed = await open(
                  context: context,
                  l10n: AppLocalizations.of(context)!,
                );
              },
              child: Text(openLabel),
            );
          },
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text(openLabel));
  await tester.pumpAndSettle();

  await tester.tap(find.text(tapLabel));
  await tester.pumpAndSettle();

  return confirmed;
}

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

  testWidgets('confirmDangerousCommandRun returns false when cancelled', (tester) async {
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
                  confirmed = await confirmDangerousCommandRun(
                    context: context,
                    l10n: AppLocalizations.of(context)!,
                    patternId: 'rm_rf',
                    patternDescription: 'Recursive delete',
                  );
                },
                child: const Text('Open dangerous command confirm'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open dangerous command confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Run high-risk command?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(confirmed, isFalse);
  });

  testWidgets('confirmDangerousCommandRun returns true when confirmed', (tester) async {
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
                  confirmed = await confirmDangerousCommandRun(
                    context: context,
                    l10n: AppLocalizations.of(context)!,
                    patternId: 'rm_rf',
                    patternDescription: 'Recursive delete',
                  );
                },
                child: const Text('Open dangerous command confirm'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open dangerous command confirm'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Run anyway'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  testWidgets('confirmEnableRemoteAgentAction shows Enable remote title and returns true', (tester) async {
    final confirmed = await _runConfirmAndTap(
      tester: tester,
      open: confirmEnableRemoteAgentAction,
      openLabel: 'Open remote confirm',
      tapLabel: 'Enable remote',
    );
    expect(confirmed, isTrue);
  });

  testWidgets('confirmEnableRemoteAgentAction returns false when cancelled', (tester) async {
    final confirmed = await _runConfirmAndTap(
      tester: tester,
      open: confirmEnableRemoteAgentAction,
      openLabel: 'Open remote confirm',
      tapLabel: 'Cancel',
    );
    expect(confirmed, isFalse);
  });

  testWidgets('confirmEnableRemoteAdHocAgentAction shows ad-hoc warning and returns true', (tester) async {
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
                  confirmed = await confirmEnableRemoteAdHocAgentAction(
                    context: context,
                    l10n: AppLocalizations.of(context)!,
                  );
                },
                child: const Text('Open ad-hoc confirm'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open ad-hoc confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Enable remote ad-hoc commands?'), findsOneWidget);

    await tester.tap(find.text('Enable ad-hoc'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  testWidgets('confirmEnableRemoteAdHocAgentAction returns false when cancelled', (tester) async {
    final confirmed = await _runConfirmAndTap(
      tester: tester,
      open: confirmEnableRemoteAdHocAgentAction,
      openLabel: 'Open ad-hoc confirm',
      tapLabel: 'Cancel',
    );
    expect(confirmed, isFalse);
  });

  testWidgets('confirmReapproveRemoteAgentAction shows reapproval title and returns true', (tester) async {
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
                  confirmed = await confirmReapproveRemoteAgentAction(
                    context: context,
                    l10n: AppLocalizations.of(context)!,
                  );
                },
                child: const Text('Open reapproval confirm'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open reapproval confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Re-approve remote execution?'), findsOneWidget);

    await tester.tap(find.text('Re-approve'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  testWidgets('confirmReapproveRemoteAgentAction returns false when cancelled', (tester) async {
    final confirmed = await _runConfirmAndTap(
      tester: tester,
      open: confirmReapproveRemoteAgentAction,
      openLabel: 'Open reapproval confirm',
      tapLabel: 'Cancel',
    );
    expect(confirmed, isFalse);
  });

  testWidgets('confirmAppCloseTrigger shows app-close warning and returns true', (tester) async {
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
                  confirmed = await confirmAppCloseTrigger(
                    context: context,
                    l10n: AppLocalizations.of(context)!,
                  );
                },
                child: const Text('Open app-close confirm'),
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Open app-close confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Add app-close trigger?'), findsOneWidget);

    await tester.tap(find.text('Use app close'));
    await tester.pumpAndSettle();

    expect(confirmed, isTrue);
  });

  testWidgets('confirmAppCloseTrigger returns false when cancelled', (tester) async {
    final confirmed = await _runConfirmAndTap(
      tester: tester,
      open: confirmAppCloseTrigger,
      openLabel: 'Open app-close confirm',
      tapLabel: 'Cancel',
    );
    expect(confirmed, isFalse);
  });
}
