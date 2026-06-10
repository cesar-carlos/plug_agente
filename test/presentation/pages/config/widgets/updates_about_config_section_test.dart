import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/utils/external_url_launcher.dart';
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
    String? autoUpdateFeedStatus,
    bool updateNotificationsEnabled = true,
    bool automaticSilentUpdatesEnabled = true,
    bool isCheckingUpdates = false,
    bool isAutoUpdateAvailable = true,
    String? unavailableMessage,
    String appVersion = '1.2.6+1',
    Locale locale = const Locale('pt'),
    VoidCallback? onCheckUpdates,
    VoidCallback? onCheckAutomaticUpdates,
    VoidCallback? onCopyUpdateDiagnostics,
    ValueChanged<bool>? onUpdateNotificationsChanged,
    ValueChanged<bool>? onAutomaticSilentUpdatesChanged,
    VoidCallback? onUseManualOnlyUpdateMode,
    String? pendingUpdateNotice,
    String? releaseNotes,
    String? releaseNotesUrl,
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
              autoUpdateFeedStatus: autoUpdateFeedStatus ?? ptL10n.configAutoUpdateFeedOfficial,
              updateNotificationsEnabled: updateNotificationsEnabled,
              automaticSilentUpdatesEnabled: automaticSilentUpdatesEnabled,
              isCheckingUpdates: isCheckingUpdates,
              isAutoUpdateAvailable: isAutoUpdateAvailable,
              unavailableMessage: unavailableMessage,
              releaseNotes: releaseNotes,
              releaseNotesUrl: releaseNotesUrl,
              onCheckUpdates: onCheckUpdates ?? () {},
              onCheckAutomaticUpdates: onCheckAutomaticUpdates ?? () {},
              onCopyUpdateDiagnostics: onCopyUpdateDiagnostics ?? () {},
              onUpdateNotificationsChanged: onUpdateNotificationsChanged ?? (_) {},
              onAutomaticSilentUpdatesChanged: onAutomaticSilentUpdatesChanged ?? (_) {},
              onUseManualOnlyUpdateMode: onUseManualOnlyUpdateMode ?? () {},
              pendingUpdateNotice: pendingUpdateNotice,
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
      'shows manual check button when not checking and supports auto update',
      (tester) async {
        await pumpSection(tester);

        expect(find.text(ptL10n.configManualCheckSectionTitle), findsOneWidget);
        expect(find.byKey(const ValueKey('updates_check_now_button')), findsOneWidget);
        expect(find.byKey(const ValueKey('updates_progress_ring')), findsNothing);
      },
    );

    testWidgets('shows progress ring when isCheckingUpdates is true', (tester) async {
      await pumpSection(tester, isCheckingUpdates: true, settle: false);

      expect(find.byKey(const ValueKey('updates_check_now_button')), findsOneWidget);
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
        expect(find.byKey(const ValueKey('updates_check_now_button')), findsNothing);
        expect(find.byKey(const ValueKey('updates_progress_ring')), findsNothing);
      },
    );

    testWidgets(
      'shows configLastUpdateNever when lastUpdateCheck is empty',
      (tester) async {
        await pumpSection(tester);

        expect(find.textContaining(ptL10n.configLastUpdateNever), findsWidgets);
      },
    );

    testWidgets(
      'always shows automatic update last attempt and feed status',
      (tester) async {
        await pumpSection(tester);

        expect(
          find.text('${ptL10n.configLastAutomaticUpdatePrefix}${ptL10n.configLastUpdateNever}'),
          findsOneWidget,
        );
        expect(find.text(ptL10n.configAutoUpdateFeedOfficial), findsOneWidget);
      },
    );

    testWidgets(
      'shows custom feed status when provided',
      (tester) async {
        await pumpSection(
          tester,
          autoUpdateFeedStatus: ptL10n.configAutoUpdateFeedCustom,
        );

        expect(find.text(ptL10n.configAutoUpdateFeedCustom), findsOneWidget);
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

    testWidgets('update notifications toggle triggers callback', (tester) async {
      bool? value;
      await pumpSection(
        tester,
        onUpdateNotificationsChanged: (next) => value = next,
      );

      await tester.tap(find.byKey(const ValueKey('update_notifications_toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(value, isFalse);
    });

    testWidgets('automatic updates toggle triggers callback', (tester) async {
      bool? value;
      await pumpSection(
        tester,
        onAutomaticSilentUpdatesChanged: (next) => value = next,
      );

      await tester.tap(find.byKey(const ValueKey('automatic_silent_updates_toggle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(value, isFalse);
    });

    testWidgets('manual check button triggers onCheckUpdates callback', (tester) async {
      var tapped = false;
      await pumpSection(tester, onCheckUpdates: () => tapped = true);

      await tester.tap(find.byKey(const ValueKey('updates_check_now_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tapped, isTrue);
    });

    testWidgets('hides automatic update button when automatic install is disabled', (tester) async {
      await pumpSection(tester, automaticSilentUpdatesEnabled: false);

      expect(find.byKey(const ValueKey('automatic_updates_check_now_button')), findsNothing);
    });

    testWidgets('shows manual-only link when not already in manual-only mode', (tester) async {
      await pumpSection(tester);

      expect(find.byKey(const ValueKey('updates_manual_only_mode_link')), findsOneWidget);
    });

    testWidgets('hides manual-only link when already in manual-only mode', (tester) async {
      await pumpSection(
        tester,
        updateNotificationsEnabled: false,
        automaticSilentUpdatesEnabled: false,
      );

      expect(find.byKey(const ValueKey('updates_manual_only_mode_link')), findsNothing);
    });

    testWidgets('manual-only link triggers callback', (tester) async {
      var tapped = false;
      await pumpSection(tester, onUseManualOnlyUpdateMode: () => tapped = true);

      await tester.tap(find.byKey(const ValueKey('updates_manual_only_mode_link')));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });

    testWidgets('shows pending update notice when provided', (tester) async {
      await pumpSection(
        tester,
        pendingUpdateNotice: ptL10n.configUpdatePendingReadyNotice,
      );

      expect(find.byKey(const ValueKey('updates_pending_notice')), findsOneWidget);
      expect(find.text(ptL10n.configUpdatePendingReadyNotice), findsOneWidget);
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

    testWidgets('hides release notes expander when neither notes nor URL are set', (tester) async {
      await pumpSection(tester);

      expect(find.byKey(const ValueKey('updates_release_notes_expander')), findsNothing);
    });

    testWidgets('renders release notes expander with inline text', (tester) async {
      await pumpSection(
        tester,
        releaseNotes: '- Fixed update issue\n- Improved diagnostics',
      );

      expect(find.byKey(const ValueKey('updates_release_notes_expander')), findsOneWidget);
      expect(find.textContaining('Fixed update issue'), findsOneWidget);
    });

    testWidgets('renders release notes URL when only URL is provided', (tester) async {
      const releaseUrl = 'https://github.com/cesar-carlos/plug_agente/releases/tag/v1.7.0';
      await pumpSection(
        tester,
        releaseNotesUrl: releaseUrl,
      );

      expect(find.byKey(const ValueKey('updates_release_notes_expander')), findsOneWidget);
      expect(find.byKey(const ValueKey('updates_release_notes_link')), findsOneWidget);
      expect(find.textContaining(releaseUrl), findsOneWidget);
      expect(find.text(ptL10n.configAutoUpdateReleaseNotesLink), findsOneWidget);
    });

    testWidgets('release notes hyperlink launches external URL', (tester) async {
      const releaseUrl = 'https://example.com/releases/v1.7.0';
      final defaultLaunchCallback = ExternalUrlLauncher.launchCallback;
      String? launchedUrl;
      addTearDown(() {
        ExternalUrlLauncher.launchCallback = defaultLaunchCallback;
      });
      ExternalUrlLauncher.launchCallback = (url) async {
        launchedUrl = url;
        return true;
      };

      await pumpSection(
        tester,
        releaseNotesUrl: releaseUrl,
      );

      await tester.tap(find.text(ptL10n.configAutoUpdateReleaseNotesHeader));
      await tester.pumpAndSettle();

      await tester.tap(find.text(ptL10n.configAutoUpdateReleaseNotesLink));
      await tester.pumpAndSettle();

      expect(launchedUrl, releaseUrl);
    });
  });
}
