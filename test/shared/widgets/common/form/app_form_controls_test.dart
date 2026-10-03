import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_form_field_pair.dart';
import 'package:plug_agente/shared/widgets/common/form/app_text_field.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget child, {double scale = 1}) async {
    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: ScaffoldPage(content: child),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('dropdown with null callback cannot open its menu', (tester) async {
    await pump(
      tester,
      const AppDropdown<String>(
        label: 'Tipo',
        value: 'a',
        items: [
          ComboBoxItem(value: 'a', child: Text('A')),
          ComboBoxItem(value: 'b', child: Text('B')),
        ],
      ),
    );
    expect(tester.widget<ComboBox<String>>(find.byType(ComboBox<String>)).onChanged, isNull);
    await tester.tap(find.text('A'));
    await tester.pumpAndSettle();
    expect(find.text('B'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('paired fields stack at compact widths with enlarged fonts', (tester) async {
    await tester.binding.setSurfaceSize(const Size(500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(
      tester,
      const AppFormFieldPair(
        first: AppTextField(label: 'Primeiro campo'),
        second: AppTextField(label: 'Segundo campo'),
      ),
      scale: 1.75,
    );
    expect(
      tester.getTopLeft(find.text('Segundo campo')).dy,
      greaterThan(tester.getBottomLeft(find.text('Primeiro campo')).dy),
    );
    expect(tester.takeException(), isNull);
  });

  test('command help preserves the exact context placeholder', () async {
    final l10n = await AppLocalizations.delegate.load(const Locale('pt'));
    final help = l10n.agentActionsHelpCommandMessage(r'${context_path}');
    final warning = l10n.agentActionsCommandLineLegacyWarning(r'${context_path}');
    expect(help, contains(r'${context_path}'));
    expect(warning, contains(r'${context_path}'));
    expect(help, isNot(contains(r'\$')));
    expect(help, isNot(contains(r'$$')));
    expect(warning, isNot(contains(r'$$')));
  });
}
