import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/constants/window_constraints.dart';
import 'package:plug_agente/core/support/support_diagnostics_section.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/shared/widgets/common/feedback/message_modal.dart';

void main() {
  late AppLocalizations ptL10n;

  setUpAll(() async {
    ptL10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  Future<void> pumpDialog(
    WidgetTester tester, {
    required Size viewportSize,
    List<SupportDiagnosticsSection> diagnosticSections = const <SupportDiagnosticsSection>[],
  }) async {
    await tester.binding.setSurfaceSize(viewportSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      FluentApp(
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            return NavigationView(
              content: ScaffoldPage(
                content: Center(
                  child: Button(
                    onPressed: () {
                      MessageModal.show<void>(
                        context: context,
                        title: ptL10n.gsSectionUpdates,
                        message: ptL10n.configUpdatesNotAvailable,
                        diagnosticSections: diagnosticSections,
                      );
                    },
                    child: const Text('Open dialog'),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Open dialog'));
    await tester.pumpAndSettle();
  }

  testWidgets('uses responsive width constraints on wide screens', (tester) async {
    await pumpDialog(
      tester,
      viewportSize: const Size(1280, 800),
    );

    final dialog = tester.widget<ContentDialog>(find.byType(ContentDialog));
    expect(dialog.constraints.maxWidth, WindowConstraints.messageModalWidth);
    expect(dialog.constraints.minWidth, WindowConstraints.messageModalMinWidth);
  });

  testWidgets('resolveMessageModalConstraints narrows on compact viewports', (tester) async {
    late BoxConstraints constraints;

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(size: Size(500, 700)),
        child: Builder(
          builder: (context) {
            constraints = WindowConstraints.resolveMessageModalConstraints(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(constraints.maxWidth, lessThan(WindowConstraints.messageModalWidth));
    expect(constraints.maxWidth, greaterThanOrEqualTo(WindowConstraints.messageModalMinViewportWidth));
  });

  testWidgets('renders diagnostics expander when sections are provided', (tester) async {
    await pumpDialog(
      tester,
      viewportSize: const Size(1280, 800),
      diagnosticSections: const <SupportDiagnosticsSection>[
        SupportDiagnosticsSection(
          title: 'Detalhes técnicos',
          fields: <SupportDiagnosticsField>[
            SupportDiagnosticsField(
              key: 'Feed configurado',
              value: 'https://example.com/appcast.xml',
            ),
          ],
        ),
      ],
    );

    expect(find.text(ptL10n.configUpdateTechnicalTitle), findsOneWidget);
    expect(find.textContaining('https://example.com/appcast.xml'), findsOneWidget);
    expect(find.text(ptL10n.configAutoUpdateReleaseNotesLink), findsOneWidget);
  });
}
