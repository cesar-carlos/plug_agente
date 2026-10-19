import 'dart:ui' show Tristate;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/theme/app_theme.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/navigation/app_paged_view.dart';

void main() {
  late AppLocalizations l10n;

  setUpAll(() async {
    l10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  testWidgets('keeps offstage fields and places save beside page navigation', (tester) async {
    final name = TextEditingController(text: 'Lista');
    addTearDown(name.dispose);
    final nameFocus = FocusNode();
    addTearDown(nameFocus.dispose);
    var index = 0;

    await tester.binding.setSurfaceSize(const Size(800, 480));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('pt'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: SizedBox(
            width: 800,
            height: 480,
            child: StatefulBuilder(
              builder: (context, setState) {
                return AppPagedView(
                  pages: [
                    AppPageItem(
                      id: 'identity',
                      label: l10n.agentActionsEditorIdentityTab,
                      body: TextBox(controller: name, focusNode: nameFocus),
                    ),
                    AppPageItem(
                      id: 'target',
                      label: l10n.agentActionsEditorTargetTab,
                      body: const Text('target-body'),
                    ),
                  ],
                  currentIndex: index,
                  onPageChanged: (value) => setState(() => index = value),
                  footer: Button(onPressed: () {}, child: Text(l10n.agentActionsFormSave)),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(
      tester.getSemantics(find.byKey(const ValueKey('app_page_identity'))).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    expect(find.text(l10n.pagedViewPrevious), findsOneWidget);
    expect(find.text(l10n.agentActionsFormSave), findsOneWidget);

    await tester.enterText(find.byType(TextBox), 'Lista de Transmissao');
    await tester.tap(find.byKey(const ValueKey('app_page_target')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(index, 1);
    expect(find.text('target-body'), findsOneWidget);
    expect(name.text, 'Lista de Transmissao');
    expect(nameFocus.canRequestFocus, isFalse);
    nameFocus.requestFocus();
    await tester.pump();
    expect(nameFocus.hasFocus, isFalse);
    for (var step = 0; step < 8; step++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(nameFocus.hasFocus, isFalse);
    }
    expect(find.text(l10n.pagedViewPosition(2, 2)), findsNothing);
    expect(
      tester.getSemantics(find.byKey(const ValueKey('app_page_target'))).flagsCollection.isSelected,
      Tristate.isTrue,
    );
    await tester.tap(find.byKey(const ValueKey('app_page_identity')));
    await tester.pumpAndSettle();
    nameFocus.requestFocus();
    await tester.pump();
    expect(nameFocus.hasFocus, isTrue);
    expect(name.text, 'Lista de Transmissao');
  });

  testWidgets('wraps page tabs instead of clipping the last label', (tester) async {
    await tester.binding.setSurfaceSize(const Size(420, 360));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('pt'),
        theme: AppTheme.light(),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(
          content: SizedBox(
            width: 420,
            height: 360,
            child: AppPagedView(
              pages: [
                AppPageItem(id: 'identity', label: l10n.agentActionsEditorIdentityTab, body: const SizedBox.shrink()),
                AppPageItem(id: 'target', label: l10n.agentActionsEditorTargetTab, body: const SizedBox.shrink()),
                AppPageItem(id: 'schedule', label: l10n.agentActionsEditorScheduleTab, body: const SizedBox.shrink()),
                AppPageItem(id: 'limits', label: l10n.agentActionsEditorLimitsTab, body: const SizedBox.shrink()),
                AppPageItem(id: 'advanced', label: l10n.agentActionsEditorAdvancedTab, body: const SizedBox.shrink()),
                AppPageItem(
                  id: 'notifications',
                  label: l10n.agentActionsEditorNotificationsTab,
                  body: const SizedBox.shrink(),
                ),
              ],
              currentIndex: 0,
              onPageChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(l10n.agentActionsEditorIdentityTab), findsOneWidget);
    expect(find.text(l10n.agentActionsEditorNotificationsTab), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
