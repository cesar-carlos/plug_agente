import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/shared/widgets/common/navigation/app_fluent_tab_view.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child) async {
    await tester.pumpWidget(
      FluentApp(
        home: NavigationView(content: ScaffoldPage(content: child)),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('AppFluentTabView', () {
    testWidgets('renders SizedBox.shrink when items is empty', (tester) async {
      await pump(
        tester,
        AppFluentTabView(
          currentIndex: 0,
          onChanged: (_) {},
          items: const <AppFluentTabItem>[],
        ),
      );

      expect(find.byType(TabView), findsNothing);
    });

    testWidgets(
      'renders body directly without TabView when only one item',
      (tester) async {
        await pump(
          tester,
          AppFluentTabView(
            currentIndex: 0,
            onChanged: (_) {},
            items: const <AppFluentTabItem>[
              AppFluentTabItem(
                icon: FluentIcons.settings,
                text: 'Geral',
                body: Text('single-body', key: ValueKey('single_body_text')),
              ),
            ],
          ),
        );

        expect(find.byType(TabView), findsNothing);
        expect(find.byKey(const ValueKey('single_body_text')), findsOneWidget);
        expect(find.byKey(const ValueKey('app_fluent_tab_view_single')), findsOneWidget);
      },
    );

    testWidgets('renders TabView with strip when multiple items', (tester) async {
      await pump(
        tester,
        AppFluentTabView(
          currentIndex: 0,
          onChanged: (_) {},
          items: const <AppFluentTabItem>[
            AppFluentTabItem(
              icon: FluentIcons.settings,
              text: 'Geral',
              body: Text('body-a'),
            ),
            AppFluentTabItem(
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
