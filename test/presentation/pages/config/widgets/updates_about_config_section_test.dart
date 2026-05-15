import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/updates_about_config_section.dart';

void main() {
  late AppLocalizations ptL10n;

  setUpAll(() async {
    ptL10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    String lastUpdateCheck = '',
    String lastBackgroundUpdateCheck = '',
    String lastAutomaticUpdateCheck = '',
    bool automaticSilentUpdatesEnabled = true,
    bool isCheckingUpdates = false,
    bool isAutoUpdateAvailable = true,
    String? unavailableMessage,
    String appVersion = '1.2.6+1',
    Locale locale = const Locale('pt'),
    VoidCallback? onCheckUpdates,
    VoidCallback? onCheckAutomaticUpdates,
    VoidCallback? onCopyUpdateDiagnostics,
    ValueChanged<bool>? onAutomaticSilentUpdatesChanged,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      FluentApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NavigationView(
          content: ScaffoldPage(
            content: UpdatesAboutConfigSection(
              appVersion: appVersion,
              lastUpdateCheck: lastUpdateCheck,
              lastBackgroundUpdateCheck: lastBackgroundUpdateCheck,
              lastAutomaticUpdateCheck: lastAutomaticUpdateCheck,
              automaticSilentUpdatesEnabled: automaticSilentUpdatesEnabled,
              isCheckingUpdates: isCheckingUpdates,
              isAutoUpdateAvailable: isAutoUpdateAvailable,
              unavailableMessage: unavailableMessage,
              onCheckUpdates: onCheckUpdates ?? () {},
              onCheckAutomaticUpdates: onCheckAutomaticUpdates ?? () {},
              onCopyUpdateDiagnostics: onCopyUpdateDiagnostics ?? () {},
              onAutomaticSilentUpdatesChanged: onAutomaticSilentUpdatesChanged ?? (_) {},
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
  }

  group('UpdatesAboutConfigSection - layout', () {
    testWidgets('renders updates and about section titles', (tester) async {
      await pumpSection(tester);

      expect(find.text(ptL10n.gsSectionUpdates), findsOneWidget);
      expect(find.text(ptL10n.gsSectionAbout), findsOneWidget);
    });

    testWidgets('renders the provided app version', (tester) async {
      await pumpSection(tester, appVersion: '9.9.9+42');

      expect(find.text('9.9.9+42'), findsOneWidget);
    });
  });

  group('UpdatesAboutConfigSection - updates section', () {
    testWidgets(
      'shows refresh button when not checking and supports auto update',
      (tester) async {
        await pumpSection(tester);

        expect(find.byKey(const ValueKey('updates_refresh_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('updates_progress_ring')), findsNothing);
      },
    );

    testWidgets('shows progress ring when isCheckingUpdates is true', (tester) async {
      await pumpSection(tester, isCheckingUpdates: true, settle: false);

      expect(find.byKey(const ValueKey('updates_refresh_button')), findsNothing);
      expect(find.byKey(const ValueKey('updates_progress_ring')), findsOneWidget);
    });

    testWidgets(
      'shows configAutoUpdateNotSupported when update is unavailable',
      (tester) async {
        await pumpSection(
          tester,
          isAutoUpdateAvailable: false,
          unavailableMessage: ptL10n.configAutoUpdateNotSupported,
        );

        expect(find.text(ptL10n.configAutoUpdateNotSupported), findsOneWidget);
        expect(find.byKey(const ValueKey('updates_refresh_button')), findsNothing);
        expect(find.byKey(const ValueKey('updates_progress_ring')), findsNothing);
      },
    );

    testWidgets(
      'shows configLastUpdateNever when lastUpdateCheck is empty',
      (tester) async {
        await pumpSection(tester);

        expect(find.textContaining(ptL10n.configLastUpdateNever), findsOneWidget);
      },
    );

    testWidgets(
      'shows lastUpdateCheck verbatim when provided',
      (tester) async {
        const last = 'Última verificação: 18/04/2026 18:30';
        await pumpSection(tester, lastUpdateCheck: last);

        expect(find.textContaining(last), findsOneWidget);
      },
    );

    testWidgets(
      'shows background update label when provided',
      (tester) async {
        const background = 'Última verificação automática: 08/05/2026 09:15 - Sem atualização disponível';
        await pumpSection(
          tester,
          lastBackgroundUpdateCheck: background,
        );

        expect(find.textContaining(background), findsOneWidget);
      },
    );

    testWidgets(
      'shows automatic update label when provided',
      (tester) async {
        final automatic =
            '${ptL10n.configLastAutomaticUpdatePrefix}14/05/2026 11:20 - ${ptL10n.configUpdateCompletionSourceAutomaticInstallStarted}';
        await pumpSection(
          tester,
          lastAutomaticUpdateCheck: automatic,
        );

        expect(find.textContaining(automatic), findsOneWidget);
      },
    );

    testWidgets('automatic updates toggle triggers callback', (tester) async {
      bool? value;
      await pumpSection(
        tester,
        onAutomaticSilentUpdatesChanged: (next) => value = next,
      );

      await tester.tap(find.byType(ToggleSwitch));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(value, isFalse);
    });

    testWidgets('refresh button triggers onCheckUpdates callback', (tester) async {
      var tapped = false;
      await pumpSection(tester, onCheckUpdates: () => tapped = true);

      await tester.tap(find.byKey(const ValueKey('updates_refresh_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tapped, isTrue);
    });

    testWidgets('automatic update button triggers silent check callback', (tester) async {
      var tapped = false;
      await pumpSection(tester, onCheckAutomaticUpdates: () => tapped = true);

      await tester.tap(find.byKey(const ValueKey('automatic_updates_check_now_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(tapped, isTrue);
    });

    testWidgets('copy diagnostics button triggers callback', (tester) async {
      var copied = false;
      await pumpSection(
        tester,
        onCopyUpdateDiagnostics: () => copied = true,
      );

      await tester.tap(find.byKey(const ValueKey('updates_copy_diagnostics_button')));
      await tester.pumpAndSettle();

      expect(copied, isTrue);
    });
  });
}
