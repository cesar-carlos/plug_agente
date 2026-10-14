import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/agent_profile/widgets/responsive_field_row.dart';
import 'package:plug_agente/shared/widgets/common/form/app_dropdown.dart';
import 'package:plug_agente/shared/widgets/common/form/app_form_feedback_scope.dart';
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

  testWidgets('text field shows a scope error before it is edited', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await pump(
      tester,
      AppFormFeedbackScope(
        errors: {controller: 'Nome é obrigatório'},
        requiredControllers: {controller},
        requiredHint: 'Obrigatório',
        optionalHint: 'Opcional',
        focusController: null,
        focusRequest: 0,
        onChanged: (_) {},
        child: AppTextField(label: 'Nome', controller: controller),
      ),
    );

    expect(find.text('Nome é obrigatório'), findsOneWidget);
    expect(find.text('Obrigatório'), findsNothing);
  });

  testWidgets('text field shows the required hint when the scope has no error', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await pump(
      tester,
      AppFormFeedbackScope(
        errors: const <TextEditingController, String>{},
        requiredControllers: {controller},
        requiredHint: 'Obrigatório',
        optionalHint: 'Opcional',
        focusController: null,
        focusRequest: 0,
        onChanged: (_) {},
        child: AppTextField(label: 'Nome', controller: controller),
      ),
    );

    expect(find.text('Obrigatório'), findsOneWidget);
  });

  testWidgets('text field shows its validator only after an edit', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await pump(
      tester,
      AppTextField(
        label: 'Nome',
        controller: controller,
        validator: (_) => 'Valor inválido',
      ),
    );

    expect(find.text('Valor inválido'), findsNothing);
    await tester.enterText(find.byType(TextBox), 'a');
    await tester.pump();
    expect(find.text('Valor inválido'), findsOneWidget);
  });

  testWidgets('dropdown shows a scope error and clears its key', (tester) async {
    Object? cleared;

    await pump(
      tester,
      AppFormFeedbackScope(
        errors: const <TextEditingController, String>{},
        requiredControllers: const <TextEditingController>{},
        requiredHint: 'Obrigatório',
        optionalHint: 'Opcional',
        focusController: null,
        focusRequest: 1,
        onChanged: (_) {},
        keyedErrors: const <Object, String>{'kind': 'Escolha um tipo'},
        requiredKeys: const <Object>{'kind'},
        focusKey: 'kind',
        onKeyedChanged: (key) => cleared = key,
        child: AppDropdown<String>(
          label: 'Tipo',
          feedbackKey: 'kind',
          value: 'a',
          items: const [
            ComboBoxItem(value: 'a', child: Text('A')),
            ComboBoxItem(value: 'b', child: Text('B')),
          ],
          onChanged: (_) {},
        ),
      ),
    );
    await tester.pump();

    expect(find.text('Escolha um tipo'), findsOneWidget);
    expect(tester.binding.focusManager.primaryFocus?.hasFocus, isTrue);

    await tester.tap(find.byType(ComboBox<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('B').last);
    await tester.pumpAndSettle();

    expect(cleared, 'kind');
  });

  testWidgets('dropdown shows the required hint when the scope has no error', (tester) async {
    await pump(
      tester,
      AppFormFeedbackScope(
        errors: const <TextEditingController, String>{},
        requiredControllers: const <TextEditingController>{},
        requiredHint: 'Obrigatório',
        optionalHint: 'Opcional',
        focusController: null,
        focusRequest: 0,
        onChanged: (_) {},
        requiredKeys: const <Object>{'kind'},
        child: AppDropdown<String>(
          label: 'Tipo',
          feedbackKey: 'kind',
          value: 'a',
          items: const [ComboBoxItem(value: 'a', child: Text('A'))],
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Obrigatório'), findsOneWidget);
  });

  testWidgets('unchanged feedback does not rebuild dependent fields', (tester) async {
    await tester.pumpWidget(
      const FluentApp(
        locale: Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ScaffoldPage(content: _FeedbackHost()),
      ),
    );
    final state = tester.state<_FeedbackHostState>(find.byType(_FeedbackHost));
    final built = state.builds;

    state.rebuildSameFeedback();
    await tester.pump();
    expect(state.builds, built);

    state.rebuildWithError();
    await tester.pump();
    expect(state.builds, built + 1);
    expect(find.text('Falhou'), findsOneWidget);
  });

  testWidgets('profile rows use the same scaled breakpoint as form pairs', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await pump(
      tester,
      const ResponsiveFieldRow(
        children: [
          Text('Primeiro campo'),
          Text('Segundo campo'),
        ],
      ),
      scale: 1.75,
    );

    expect(
      tester.getTopLeft(find.text('Segundo campo')).dy,
      greaterThan(tester.getBottomLeft(find.text('Primeiro campo')).dy),
    );
    expect(tester.takeException(), isNull);
  });
}

class _FeedbackHost extends StatefulWidget {
  const _FeedbackHost();

  @override
  State<_FeedbackHost> createState() => _FeedbackHostState();
}

class _FeedbackHostState extends State<_FeedbackHost> {
  var builds = 0;
  final TextEditingController controller = TextEditingController();
  String? error;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void rebuildSameFeedback() => setState(() {});

  void rebuildWithError() => setState(() => error = 'Falhou');

  @override
  Widget build(BuildContext context) {
    return AppFormFeedbackScope(
      errors: {if (error != null) controller: error!},
      requiredControllers: {controller},
      requiredHint: 'Obrigatório',
      optionalHint: 'Opcional',
      focusController: null,
      focusRequest: 0,
      onChanged: (_) {},
      child: const _FeedbackProbe(),
    );
  }
}

class _FeedbackProbe extends StatelessWidget {
  const _FeedbackProbe();

  @override
  Widget build(BuildContext context) {
    context.findAncestorStateOfType<_FeedbackHostState>()!.builds++;
    final feedback = AppFormFeedbackScope.maybeOf(context);
    final message = feedback?.errors.values.firstOrNull;
    return Text(message ?? 'sem erro');
  }
}
