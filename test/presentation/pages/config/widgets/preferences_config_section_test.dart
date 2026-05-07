import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
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
    bool startMinimized = false,
    bool minimizeToTray = true,
    bool closeToTray = true,
    bool startupSupported = true,
    SystemSettingsErrorState? startupError,
    Locale locale = const Locale('pt'),
    void Function(bool)? onDarkThemeChanged,
    void Function(bool)? onStartWithWindowsChanged,
    void Function(bool)? onStartMinimizedChanged,
    void Function(bool)? onMinimizeToTrayChanged,
    void Function(bool)? onCloseToTrayChanged,
    VoidCallback? onOpenStartupSettings,
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
              startMinimized: startMinimized,
              minimizeToTray: minimizeToTray,
              closeToTray: closeToTray,
              startupSupported: startupSupported,
              startupError: startupError,
              onDarkThemeChanged: onDarkThemeChanged ?? (_) {},
              onStartWithWindowsChanged: onStartWithWindowsChanged ?? (_) {},
              onStartMinimizedChanged: onStartMinimizedChanged ?? (_) {},
              onMinimizeToTrayChanged: onMinimizeToTrayChanged ?? (_) {},
              onCloseToTrayChanged: onCloseToTrayChanged ?? (_) {},
              onOpenStartupSettings: onOpenStartupSettings ?? () {},
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
  });

  group('PreferencesConfigSection - typed startup error rendering', () {
    testWidgets('does not render error block when startupError is null', (tester) async {
      await pumpSection(tester);
      expect(find.byIcon(FluentIcons.error_badge), findsNothing);
      expect(find.text(ptL10n.gsButtonOpenSettings), findsNothing);
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

    testWidgets('translates startupToggleFailed with detail using gsErrorWithDetail', (tester) async {
      await pumpSection(
        tester,
        startupError: const SystemSettingsErrorState(
          code: SystemSettingsErrorCode.startupToggleFailed,
          detail: 'Registry access denied',
        ),
      );

      final expected = ptL10n.gsErrorWithDetail(
        ptL10n.gsErrorStartupToggleFailed,
        'Registry access denied',
      );
      expect(find.text(expected), findsOneWidget);
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
