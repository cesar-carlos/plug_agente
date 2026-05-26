import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/main_window.dart';
import 'package:plug_agente/presentation/providers/runtime_mode_provider.dart';
import 'package:provider/provider.dart';

void main() {
  late AppLocalizations ptL10n;

  setUpAll(() async {
    ptL10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  Future<void> pumpWindow(
    WidgetTester tester, {
    required RuntimeCapabilities capabilities,
  }) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) {
            return ChangeNotifierProvider(
              create: (_) => RuntimeModeProvider(capabilities),
              child: const MainWindow(
                child: Center(child: Text('Dashboard')),
              ),
            );
          },
        ),
      ],
    );

    await tester.pumpWidget(
      FluentApp.router(
        routerConfig: router,
        locale: const Locale('pt'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('hides degraded banner in full runtime mode', (tester) async {
    await pumpWindow(
      tester,
      capabilities: RuntimeCapabilities.full(),
    );

    expect(find.text(ptL10n.mainDegradedModeTitle), findsNothing);
  });

  testWidgets('shows degraded banner and reasons in degraded runtime mode', (tester) async {
    await pumpWindow(
      tester,
      capabilities: RuntimeCapabilities.degraded(
        reasons: const [
          'Windows Server detectado',
          'Versão: 10.0.17763',
        ],
      ),
    );

    expect(find.text(ptL10n.mainDegradedModeTitle), findsOneWidget);
    expect(find.text(ptL10n.mainDegradedModeDescription), findsOneWidget);
    expect(find.textContaining('Windows Server detectado'), findsOneWidget);
    expect(find.textContaining('10.0.17763'), findsOneWidget);
  });

  testWidgets('keeps unsupported runtime without degraded banner because bootstrap should block earlier', (
    tester,
  ) async {
    await pumpWindow(
      tester,
      capabilities: RuntimeCapabilities.unsupported(
        reasons: const [
          'Sistema operacional nao suportado',
        ],
      ),
    );

    expect(find.text(ptL10n.mainDegradedModeTitle), findsNothing);
  });

  testWidgets('shows degraded banner for runtime detection fallback reasons', (tester) async {
    await pumpWindow(
      tester,
      capabilities: RuntimeCapabilities.degraded(
        reasons: const [
          'Falha ao detectar versao do Windows com confianca',
          'Fallback seguro aplicado para evitar crashes de plugins desktop',
        ],
      ),
    );

    expect(find.text(ptL10n.mainDegradedModeTitle), findsOneWidget);
    expect(
      find.textContaining('Falha ao detectar versao do Windows com confianca'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Fallback seguro aplicado para evitar crashes de plugins desktop'),
      findsOneWidget,
    );
  });
}
