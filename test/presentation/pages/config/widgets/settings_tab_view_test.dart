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

    testWidgets('sizes tabs to content, keeps shortcuts off, and preserves long labels', (tester) async {
      await tester.binding.setSurfaceSize(const Size(520, 400));
      await pump(
        tester,
        const SizedBox(
          width: 520,
          height: 300,
          child: AppFluentTabView(
            currentIndex: 0,
            onChanged: _noopTabChanged,
            items: <AppFluentTabItem>[
              AppFluentTabItem(
                icon: FluentIcons.processing,
                text: 'Acoes',
                body: Text('body-a'),
              ),
              AppFluentTabItem(
                icon: FluentIcons.history,
                text: 'Historico de execucao',
                body: Text('body-b'),
              ),
              AppFluentTabItem(
                icon: FluentIcons.settings,
                text: 'Preferencias',
                body: Text('body-c'),
              ),
              AppFluentTabItem(
                icon: FluentIcons.cloud,
                text: 'Auditoria remota agent.action',
                body: Text('body-d'),
              ),
            ],
          ),
        ),
      );

      final tabView = tester.widget<TabView>(find.byType(TabView));
      expect(tabView.shortcutsEnabled, isFalse);
      expect(tabView.showScrollButtons, isTrue);
      expect(tabView.tabWidthBehavior, TabWidthBehavior.sizeToContent);
      expect(tabView.closeButtonVisibility, CloseButtonVisibilityMode.never);
      expect(tabView.tabs, hasLength(4));
      expect((tabView.tabs.last.text as Text).data, 'Auditoria remota agent.action');
      expect((tabView.tabs.last.text as Text).overflow, TextOverflow.ellipsis);
    });
  });
}

void _noopTabChanged(int index) {}
