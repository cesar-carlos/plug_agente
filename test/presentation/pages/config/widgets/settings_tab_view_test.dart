import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/presentation/pages/config/widgets/settings_tab_view.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      FluentApp(
        home: NavigationView(content: ScaffoldPage(content: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SettingsTabView', () {
    testWidgets('renders SizedBox.shrink when items is empty', (tester) async {
      await pump(
        tester,
        SettingsTabView(
          currentIndex: 0,
          onChanged: (_) {},
          items: const <SettingsTabItem>[],
        ),
      );

      expect(find.byType(TabView), findsNothing);
    });

    testWidgets(
      'renders body directly without TabView when only one item',
      (tester) async {
        await pump(
          tester,
          SettingsTabView(
            currentIndex: 0,
            onChanged: (_) {},
            items: const <SettingsTabItem>[
              SettingsTabItem(
                icon: FluentIcons.settings,
                text: 'Geral',
                body: Text('single-body', key: ValueKey('single_body_text')),
              ),
            ],
          ),
        );

        expect(find.byType(TabView), findsNothing);
        expect(find.byKey(const ValueKey('single_body_text')), findsOneWidget);
        expect(find.byKey(const ValueKey('settings_tab_view_single')), findsOneWidget);
      },
    );

    testWidgets('renders TabView with strip when multiple items', (tester) async {
      await pump(
        tester,
        SettingsTabView(
          currentIndex: 0,
          onChanged: (_) {},
          items: const <SettingsTabItem>[
            SettingsTabItem(
              icon: FluentIcons.settings,
              text: 'Geral',
              body: Text('body-a'),
            ),
            SettingsTabItem(
              icon: FluentIcons.database,
              text: 'Avançado',
              body: Text('body-b'),
            ),
          ],
        ),
      );

      expect(find.byType(TabView), findsOneWidget);
      expect(find.text('Geral'), findsOneWidget);
      expect(find.text('Avançado'), findsOneWidget);
    });
  });
}
