import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/timezone/iana_timezone_data.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/widgets/agent_actions/iana_timezone_id_field.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    ensureIanaTimeZoneDataLoaded();
    l10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  testWidgets('should fill controller when a list row is tapped', (WidgetTester tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: IanaTimezoneIdField(
                controller: controller,
                enabled: true,
                l10n: l10n,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextBox).at(1), 'Europe/London');
    await tester.pumpAndSettle();

    expect(find.text('Europe/London'), findsWidgets);

    await tester.tap(find.text('Europe/London').last);
    await tester.pumpAndSettle();

    expect(controller.text.trim(), 'Europe/London');
  });

  testWidgets('should show no-matches hint when filter matches nothing', (WidgetTester tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: IanaTimezoneIdField(
                controller: controller,
                enabled: true,
                l10n: l10n,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextBox).at(1), '__no_iana_zone_like_this__');
    await tester.pumpAndSettle();

    expect(find.text(l10n.agentActionsTriggerTimezoneNoMatches), findsOneWidget);
  });
}
