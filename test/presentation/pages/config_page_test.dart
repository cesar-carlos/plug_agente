import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/update_check_diagnostics.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config_page.dart';
import 'package:plug_agente/presentation/providers/system_settings_provider.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class FakeAutoUpdateOrchestrator implements IAutoUpdateOrchestrator {
  FakeAutoUpdateOrchestrator({
    required this.isAvailable,
    this.onCheckManual,
    this.onCheckSilently,
    this.onSetAutomaticSilentUpdatesEnabled,
    this.lastManualDiagnostics,
    this.lastBackgroundDiagnostics,
    this.lastAutomaticDiagnostics,
    this.automaticSilentUpdatesEnabled = true,
  });

  @override
  final bool isAvailable;

  @override
  bool automaticSilentUpdatesEnabled;

  @override
  UpdateCheckDiagnostics? lastManualDiagnostics;

  @override
  UpdateCheckDiagnostics? lastBackgroundDiagnostics;

  @override
  UpdateCheckDiagnostics? lastAutomaticDiagnostics;

  Future<Result<bool>> Function()? onCheckManual;
  Future<Result<bool>> Function()? onCheckSilently;
  Future<Result<void>> Function(bool value)? onSetAutomaticSilentUpdatesEnabled;
  int silentCheckCount = 0;

  @override
  Future<Result<bool>> checkManual() async {
    if (onCheckManual != null) {
      return onCheckManual!.call();
    }
    return const Success(false);
  }

  @override
  Future<void> checkInBackground() async {}

  @override
  Future<Result<bool>> checkSilently() async {
    silentCheckCount += 1;
    if (onCheckSilently != null) {
      return onCheckSilently!.call();
    }
    return const Success(false);
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<Result<void>> setAutomaticSilentUpdatesEnabled(bool enabled) async {
    automaticSilentUpdatesEnabled = enabled;
    if (onSetAutomaticSilentUpdatesEnabled != null) {
      return onSetAutomaticSilentUpdatesEnabled!.call(enabled);
    }
    return const Success(unit);
  }

  @override
  Future<void> startAutomaticChecks() async {}
}

void main() {
  late AppLocalizations ptL10n;
  late InMemoryAppSettingsStore settingsStore;

  setUpAll(() async {
    ptL10n = await AppLocalizations.delegate.load(const Locale('pt'));
  });

  setUp(() async {
    settingsStore = InMemoryAppSettingsStore();
    dotenv.clean();
    await getIt.reset();
  });

  tearDown(() async {
    dotenv.clean();
    await getIt.reset();
  });

  Future<void> pumpPage(
    WidgetTester tester, {
    required FakeAutoUpdateOrchestrator orchestrator,
  }) async {
    getIt.registerSingleton<RuntimeCapabilities>(RuntimeCapabilities.full());
    getIt.registerSingleton<IAutoUpdateOrchestrator>(orchestrator);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(settingsStore),
          ),
          ChangeNotifierProvider<SystemSettingsProvider>(
            create: (_) => SystemSettingsProvider(settingsStore),
          ),
        ],
        child: const FluentApp(
          locale: Locale('pt'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: NavigationView(
            content: ConfigPage(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows spinner only while manual update future is pending', (tester) async {
    final completer = Completer<Result<bool>>();
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      onCheckManual: () => completer.future,
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('updates_refresh_button')));
    await tester.pump();

    expect(find.byKey(const ValueKey('updates_progress_ring')), findsOneWidget);
    expect(find.byKey(const ValueKey('updates_refresh_button')), findsNothing);

    completer.complete(const Success(false));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('updates_progress_ring')), findsNothing);
    expect(find.byKey(const ValueKey('updates_refresh_button')), findsOneWidget);
  });

  testWidgets('shows failure technical details when manual check fails', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      lastManualDiagnostics: UpdateCheckDiagnostics(
        checkedAt: DateTime(2026, 5, 4, 10, 30),
        configuredFeedUrl: 'https://example.com/appcast.xml',
        requestedFeedUrl: 'https://example.com/appcast.xml?cb=1',
        currentVersion: '1.5.2+1',
        probeRequestUrl: 'https://example.com/appcast.xml?cb=1',
        completedAt: DateTime(2026, 5, 4, 10, 31),
        completionSource: UpdateCheckCompletionSource.completionTimeout,
        probeSucceeded: true,
        appcastProbeVersion: '1.5.3+1',
        errorMessage: 'Update check timed out while waiting for updater completion',
      ),
      onCheckManual: () async {
        return Failure<bool, Exception>(
          domain.ServerFailure.withContext(
            message: 'Update check timed out while waiting for updater completion',
          ),
        );
      },
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('updates_refresh_button')));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.gsSectionUpdates), findsWidgets);
    expect(
      find.textContaining('Update check timed out while waiting for updater completion'),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        '${ptL10n.configUpdateTechnicalCompletionSource}: ${ptL10n.configUpdateCompletionSourceCompletionTimeout}',
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining('${ptL10n.configUpdateTechnicalProbeRequestUrl}: https://example.com/appcast.xml?cb=1'),
      findsOneWidget,
    );
  });

  testWidgets('shows invalid override guidance when auto update feed is not xml', (tester) async {
    dotenv.loadFromString(
      envString: 'AUTO_UPDATE_FEED_URL=https://example.com/check',
    );
    final orchestrator = FakeAutoUpdateOrchestrator(isAvailable: false);

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(find.textContaining(ptL10n.configAutoUpdateNotConfigured), findsOneWidget);
    expect(
      find.textContaining(
        ptL10n.configAutoUpdateOfficialFeedExpected(officialAutoUpdateFeedUrl),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows latest automatic check details when only background diagnostics exist', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      lastBackgroundDiagnostics: UpdateCheckDiagnostics(
        checkedAt: DateTime(2026, 5, 8, 9, 15),
        configuredFeedUrl: officialAutoUpdateFeedUrl,
        requestedFeedUrl: officialAutoUpdateFeedUrl,
        currentVersion: '1.6.0+1',
        completedAt: DateTime(2026, 5, 8, 9, 15, 2),
        completionSource: UpdateCheckCompletionSource.updateNotAvailable,
        updateAvailable: false,
      ),
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('${ptL10n.configLastUpdatePrefix}08/05/2026 09:15'),
      findsOneWidget,
    );
    expect(
      find.textContaining('${ptL10n.configLastBackgroundUpdatePrefix}08/05/2026 09:15'),
      findsOneWidget,
    );
  });

  testWidgets('shows official feed and never automatic attempt by default', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(isAvailable: true);

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.configAutoUpdateFeedOfficial), findsOneWidget);
    expect(
      find.text('${ptL10n.configLastAutomaticUpdatePrefix}${ptL10n.configLastUpdateNever}'),
      findsOneWidget,
    );
  });

  testWidgets('shows custom feed when a valid override is configured', (tester) async {
    dotenv.loadFromString(
      envString: 'AUTO_UPDATE_FEED_URL=https://example.com/appcast.xml',
    );
    final orchestrator = FakeAutoUpdateOrchestrator(isAvailable: true);

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.configAutoUpdateFeedCustom), findsOneWidget);
  });

  testWidgets('toggles automatic silent updates preference', (tester) async {
    bool? capturedValue;
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      onSetAutomaticSilentUpdatesEnabled: (value) async {
        capturedValue = value;
        return const Success(unit);
      },
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.configAutomaticSilentUpdatesToggle), findsOneWidget);

    await tester.tap(find.byType(ToggleSwitch).last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(capturedValue, isFalse);
    expect(orchestrator.automaticSilentUpdatesEnabled, isFalse);
  });

  testWidgets('manual automatic update button calls silent update flow', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      onCheckSilently: () async {
        return const Success(false);
      },
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.configAutomaticSilentUpdatesCheckNow), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('automatic_updates_check_now_button')));
    await tester.pumpAndSettle();

    expect(orchestrator.silentCheckCount, 1);
  });

  testWidgets('shows automatic silent update diagnostics', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      lastAutomaticDiagnostics: UpdateCheckDiagnostics(
        checkedAt: DateTime(2026, 5, 14, 11, 20),
        configuredFeedUrl: officialAutoUpdateFeedUrl,
        requestedFeedUrl: officialAutoUpdateFeedUrl,
        currentVersion: '1.6.7+1',
        completedAt: DateTime(2026, 5, 14, 11, 21),
        completionSource: UpdateCheckCompletionSource.automaticInstallStarted,
        remoteVersion: '1.6.8+1',
        assetName: 'PlugAgente-Setup-1.6.8.exe',
        assetUrl: 'https://example.com/PlugAgente-Setup-1.6.8.exe',
        assetSize: 123,
        sha256: '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        installerPath: r'C:\PlugAgente\updates\PlugAgente-Setup-1.6.8.exe',
        installerLogPath: r'C:\PlugAgente\updates\PlugAgente-Update-1.6.8+1.log',
      ),
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('${ptL10n.configLastAutomaticUpdatePrefix}14/05/2026 11:20'),
      findsOneWidget,
    );

    expect(find.byKey(const ValueKey('updates_copy_diagnostics_button')), findsOneWidget);
  });
}
