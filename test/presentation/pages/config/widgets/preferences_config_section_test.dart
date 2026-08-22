import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config/widgets/preferences_config_section.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';

void main() {
  late AppLocalizations ptL10n;
  late AppLocalizations enL10n;

  setUpAll(() async {
    ptL10n = await AppLocalizations.delegate.load(const Locale('pt'));
    enL10n = await AppLocalizations.delegate.load(const Locale('en'));
  });

  Future<void> pumpSection(
    WidgetTester tester, {
    bool isDarkThemeEnabled = true,
    bool startWithWindows = false,
    bool minimizeToTray = true,
    bool closeToTray = true,
    bool startupSupported = true,
    bool trayBehaviorSupported = true,
    SystemSettingsErrorState? startupError,
    SystemSettingsErrorState? preferenceError,
    SystemSettingsErrorState? themeError,
    SystemSettingsNoticeState? startupNotice,
    Locale locale = const Locale('pt'),
    void Function(bool)? onDarkThemeChanged,
    void Function(bool)? onStartWithWindowsChanged,
    void Function(bool)? onMinimizeToTrayChanged,
    void Function(bool)? onCloseToTrayChanged,
    VoidCallback? onOpenStartupSettings,
    VoidCallback? onRepairStartupLaunchConfiguration,
    VoidCallback? onCopyStartupDiagnostic,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      FluentApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: NavigationView(
          content: ScaffoldPage(
            content: PreferencesConfigSection(
              isDarkThemeEnabled: isDarkThemeEnabled,
              startWithWindows: startWithWindows,
              minimizeToTray: minimizeToTray,
              closeToTray: closeToTray,
              startupSupported: startupSupported,
              trayBehaviorSupported: trayBehaviorSupported,
              startupError: startupError,
              preferenceError: preferenceError,
              themeError: themeError,
              startupNotice: startupNotice,
              onDarkThemeChanged: onDarkThemeChanged ?? (_) {},
              onStartWithWindowsChanged: onStartWithWindowsChanged ?? (_) {},
              onMinimizeToTrayChanged: onMinimizeToTrayChanged ?? (_) {},
              onCloseToTrayChanged: onCloseToTrayChanged ?? (_) {},
              onOpenStartupSettings: onOpenStartupSettings ?? () {},
              onRepairStartupLaunchConfiguration: onRepairStartupLaunchConfiguration ?? () {},
              onCopyStartupDiagnostic: onCopyStartupDiagnostic ?? () {},
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

  group('PreferencesConfigSection - layout & sections', () {
    testWidgets('renders appearance and system section titles in PT', (tester) async {
      await pumpSection(tester);

      expect(find.text(ptL10n.gsSectionAppearance), findsOneWidget);
      expect(find.text(ptL10n.gsSectionSystem), findsOneWidget);
    });

    testWidgets('renders appearance and system section titles in EN', (tester) async {
      await pumpSection(tester, locale: const Locale('en'));

      expect(find.text(enL10n.gsSectionAppearance), findsOneWidget);
      expect(find.text(enL10n.gsSectionSystem), findsOneWidget);
    });
  });

  group('PreferencesConfigSection - startup support', () {
    Finder findToggleFor(String label) => find.descendant(
      of: find.ancestor(
        of: find.text(label),
        matching: find.byType(Row),
      ),
      matching: find.byType(ToggleSwitch),
    );

    testWidgets(
      'startWithWindows toggle is disabled when startupSupported is false',
      (tester) async {
        await pumpSection(tester, startupSupported: false);

        final toggle = tester.widget<ToggleSwitch>(
          findToggleFor(ptL10n.gsToggleStartWithWindows),
        );
        expect(toggle.onChanged, isNull);
      },
    );

    testWidgets(
      'startWithWindows toggle is enabled when startupSupported is true',
      (tester) async {
        bool? captured;
        await pumpSection(
          tester,
          onStartWithWindowsChanged: (v) => captured = v,
        );

        final toggle = tester.widget<ToggleSwitch>(
          findToggleFor(ptL10n.gsToggleStartWithWindows),
        );
        expect(toggle.onChanged, isNotNull);
        toggle.onChanged!(true);
        expect(captured, isTrue);
      },
    );

    testWidgets('does not render a start-minimized toggle', (tester) async {
      await pumpSection(tester, startWithWindows: true);

      expect(find.text(ptL10n.gsToggleStartWithWindows), findsOneWidget);
      expect(find.text(ptL10n.gsToggleMinimizeToTray), findsOneWidget);
      expect(find.text('Iniciar minimizado'), findsNothing);
      expect(find.text('Start minimized'), findsNothing);
    });

    testWidgets('startWithWindows shows admin hint when supported', (tester) async {
      await pumpSection(tester);

      expect(find.text(ptL10n.gsToggleStartWithWindowsAdminHint), findsOneWidget);
    });

    testWidgets('startWithWindows hides admin hint when not supported', (tester) async {
      await pumpSection(tester, startupSupported: false);

      expect(find.text(ptL10n.gsToggleStartWithWindowsAdminHint), findsNothing);
    });

    testWidgets(
      'minimizeToTray toggle is disabled when tray support is unavailable',
      (tester) async {
        await pumpSection(
          tester,
          trayBehaviorSupported: false,
        );

        final toggle = tester.widget<ToggleSwitch>(
          findToggleFor(ptL10n.gsToggleMinimizeToTray),
        );
        expect(toggle.onChanged, isNull);
        expect(find.text(ptL10n.gsToggleStartMinimizedRequiresTray), findsWidgets);
      },
    );

    testWidgets(
      'closeToTray toggle is disabled when tray support is unavailable',
      (tester) async {
        await pumpSection(
          tester,
          trayBehaviorSupported: false,
        );

        final toggle = tester.widget<ToggleSwitch>(
          findToggleFor(ptL10n.gsToggleCloseToTray),
        );
        expect(toggle.onChanged, isNull);
        expect(find.text(ptL10n.gsToggleStartMinimizedRequiresTray), findsWidgets);
      },
    );
  });

  group('PreferencesConfigSection - typed startup error rendering', () {
    testWidgets('does not render error block when startupError is null and startup is off', (tester) async {
      await pumpSection(tester);
      expect(find.byIcon(FluentIcons.error_badge), findsNothing);
      expect(find.text(ptL10n.gsButtonOpenSettings), findsNothing);
      expect(find.text(ptL10n.gsToggleStartWithWindowsOpenStartupAppsHint), findsNothing);
    });

    testWidgets('shows Startup Apps hint and open settings when start with Windows is on', (tester) async {
      var openedSettings = false;
      await pumpSection(
        tester,
        startWithWindows: true,
        onOpenStartupSettings: () => openedSettings = true,
      );

      expect(find.text(ptL10n.gsToggleStartWithWindowsAdminHint), findsOneWidget);
      expect(find.text(ptL10n.gsToggleStartWithWindowsOpenStartupAppsHint), findsOneWidget);
      expect(find.text(ptL10n.gsButtonOpenSettings), findsOneWidget);
      expect(find.byIcon(FluentIcons.info), findsOneWidget);

      await tester.tap(find.text(ptL10n.gsButtonOpenSettings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(openedSettings, isTrue);
    });

    testWidgets('translates startupToggleFailed without detail', (tester) async {
      await pumpSection(
        tester,
        startupError: const SystemSettingsErrorState(
          code: SystemSettingsErrorCode.startupToggleFailed,
        ),
      );

      expect(find.text(ptL10n.gsErrorStartupToggleFailed), findsOneWidget);
      expect(find.byIcon(FluentIcons.error_badge), findsOneWidget);
      expect(find.text(ptL10n.gsButtonOpenSettings), findsOneWidget);
    });

    testWidgets('translates startupToggleFailed with localized failure hint', (tester) async {
      await pumpSection(
        tester,
        startupError: const SystemSettingsErrorState(
          code: SystemSettingsErrorCode.startupToggleFailed,
          startupFailureCode: StartupServiceFailureCode.accessDenied,
        ),
      );

      expect(find.textContaining(ptL10n.gsErrorStartupToggleFailed), findsOneWidget);
      expect(find.textContaining(ptL10n.gsStartupFailureAccessDenied), findsOneWidget);
    });

    testWidgets('translates startupServiceUnavailable', (tester) async {
      await pumpSection(
        tester,
        startupError: const SystemSettingsErrorState(
          code: SystemSettingsErrorCode.startupServiceUnavailable,
        ),
      );

      expect(find.text(ptL10n.gsErrorStartupServiceUnavailable), findsOneWidget);
    });

    testWidgets('translates startupOpenSystemSettingsFailed', (tester) async {
      await pumpSection(
        tester,
        startupError: const SystemSettingsErrorState(
          code: SystemSettingsErrorCode.startupOpenSystemSettingsFailed,
          detail: 'Cannot launch shell',
        ),
      );

      final expected = ptL10n.gsErrorWithDetail(
        ptL10n.gsErrorStartupOpenSystemSettingsFailed,
        'Cannot launch shell',
      );
      expect(find.text(expected), findsOneWidget);
    });

    testWidgets('translates settingsPersistenceFailed without technical detail', (tester) async {
      await pumpSection(
        tester,
        preferenceError: const SystemSettingsErrorState(
          code: SystemSettingsErrorCode.settingsPersistenceFailed,
        ),
      );

      expect(find.text(ptL10n.gsErrorSettingsPersistenceFailed), findsOneWidget);
      expect(find.textContaining('settings.json'), findsNothing);
    });

    testWidgets('renders theme persistence error in the appearance section', (tester) async {
      await pumpSection(
        tester,
        themeError: const SystemSettingsErrorState(
          code: SystemSettingsErrorCode.settingsPersistenceFailed,
        ),
      );

      expect(find.text(ptL10n.gsErrorSettingsPersistenceFailed), findsOneWidget);
      expect(find.byIcon(FluentIcons.error_badge), findsOneWidget);
    });

    testWidgets('renders repaired startup launch notice as informational feedback', (tester) async {
      await pumpSection(
        tester,
        startupNotice: const SystemSettingsNoticeState(
          code: SystemSettingsNoticeCode.startupLaunchConfigurationRepaired,
        ),
      );

      expect(find.text(ptL10n.gsStartupLaunchConfigurationRepaired), findsOneWidget);
      expect(find.byIcon(FluentIcons.completed), findsOneWidget);
      expect(find.text(ptL10n.gsButtonRepairStartup), findsNothing);
    });

    testWidgets('renders repair failed notice with repair and diagnostic actions', (tester) async {
      var repairTapped = false;
      var diagnosticTapped = false;
      await pumpSection(
        tester,
        startupNotice: const SystemSettingsNoticeState(
          code: SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed,
          startupFailureCode: StartupServiceFailureCode.accessDenied,
        ),
        onRepairStartupLaunchConfiguration: () => repairTapped = true,
        onCopyStartupDiagnostic: () => diagnosticTapped = true,
      );

      expect(find.textContaining(ptL10n.gsStartupLaunchConfigurationRepairFailed), findsOneWidget);
      expect(find.textContaining(ptL10n.gsStartupFailureAccessDenied), findsOneWidget);
      expect(find.text(ptL10n.gsButtonRepairStartup), findsOneWidget);
      expect(find.text(ptL10n.gsButtonCopyStartupDiagnostic), findsOneWidget);

      await tester.tap(find.text(ptL10n.gsButtonRepairStartup));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(repairTapped, isTrue);

      await tester.tap(find.text(ptL10n.gsButtonCopyStartupDiagnostic));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(diagnosticTapped, isTrue);
    });

    testWidgets('renders legacy machine entry notice as informational feedback', (tester) async {
      await pumpSection(
        tester,
        startupNotice: const SystemSettingsNoticeState(
          code: SystemSettingsNoticeCode.startupLaunchConfigurationRepairedWithLegacyEntry,
        ),
      );

      expect(find.text(ptL10n.gsStartupLaunchConfigurationRepairedWithLegacyEntry), findsOneWidget);
      expect(find.byIcon(FluentIcons.info), findsOneWidget);
      expect(find.text(ptL10n.gsButtonRepairStartup), findsOneWidget);
    });

    testWidgets('offers Repair when persist and OS rollback both fail', (tester) async {
      var repairTapped = false;
      var settingsTapped = false;
      await pumpSection(
        tester,
        startupError: const SystemSettingsErrorState(
          code: SystemSettingsErrorCode.startupToggleFailed,
          startupFailureCode: StartupServiceFailureCode.rollbackFailed,
        ),
        onRepairStartupLaunchConfiguration: () => repairTapped = true,
        onOpenStartupSettings: () => settingsTapped = true,
      );

      expect(find.textContaining(ptL10n.gsErrorStartupToggleFailed), findsOneWidget);
      expect(find.textContaining(ptL10n.gsStartupFailureRollbackFailed), findsOneWidget);
      expect(find.text(ptL10n.gsButtonRepairStartup), findsOneWidget);
      expect(find.text(ptL10n.gsButtonOpenSettings), findsOneWidget);

      await tester.tap(find.text(ptL10n.gsButtonRepairStartup));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(repairTapped, isTrue);

      await tester.tap(find.text(ptL10n.gsButtonOpenSettings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(settingsTapped, isTrue);
    });

    testWidgets('open settings button triggers callback', (tester) async {
      var tapped = false;
      await pumpSection(
        tester,
        startupError: const SystemSettingsErrorState(
          code: SystemSettingsErrorCode.startupToggleFailed,
        ),
        onOpenStartupSettings: () => tapped = true,
      );

      await tester.tap(find.text(ptL10n.gsButtonOpenSettings));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(tapped, isTrue);
    });
  });
}
