import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/app_preferences_repository.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/config/auto_update_feed_config.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/runtime/runtime_detection_diagnostics.dart';
import 'package:plug_agente/core/runtime/windows_version_info.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/repositories/startup_preferences_repository.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/pages/config_page.dart';
import 'package:plug_agente/presentation/providers/presentation_infrastructure_providers.dart';
import 'package:plug_agente/presentation/providers/system_settings_provider.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:plug_agente/presentation/providers/updates_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class MockStartupService extends Mock implements IStartupService {}

class FakeAutoUpdateOrchestrator implements IAutoUpdateOrchestrator {
  FakeAutoUpdateOrchestrator({
    required this.isAvailable,
    this.onCheckManual,
    this.onCheckSilently,
    this.onSetAutomaticSilentUpdatesEnabled,
    this.onSetUpdateNotificationsEnabled,
    this.lastManualDiagnostics,
    this.lastBackgroundDiagnostics,
    this.lastAutomaticDiagnostics,
    this.automaticSilentUpdatesEnabled = true,
    this.updateNotificationsEnabled = true,
  });

  @override
  final bool isAvailable;

  @override
  bool automaticSilentUpdatesEnabled;

  @override
  bool updateNotificationsEnabled;

  @override
  bool isSilentCheckInProgress = false;

  @override
  UpdateCheckDiagnostics? lastManualDiagnostics;

  @override
  UpdateCheckDiagnostics? lastBackgroundDiagnostics;

  @override
  UpdateCheckDiagnostics? lastAutomaticDiagnostics;

  Future<Result<ManualCheckOutcome>> Function()? onCheckManual;
  Future<Result<SilentUpdateOutcome>> Function()? onCheckSilently;
  Future<Result<void>> Function(bool value)? onSetAutomaticSilentUpdatesEnabled;
  Future<Result<void>> Function(bool value)? onSetUpdateNotificationsEnabled;
  int silentCheckCount = 0;

  @override
  Future<Result<ManualCheckOutcome>> checkManual() async {
    if (onCheckManual != null) {
      return onCheckManual!.call();
    }
    return const Success(ManualCheckOutcome.noUpdate);
  }

  @override
  Future<void> checkInBackground() async {}

  @override
  Future<Result<SilentUpdateOutcome>> checkSilently() async {
    silentCheckCount += 1;
    if (onCheckSilently != null) {
      return onCheckSilently!.call();
    }
    return const Success(SilentUpdateOutcome.noNewVersion);
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
  Future<Result<void>> setUpdateNotificationsEnabled(bool enabled) async {
    updateNotificationsEnabled = enabled;
    if (onSetUpdateNotificationsEnabled != null) {
      return onSetUpdateNotificationsEnabled!.call(enabled);
    }
    return const Success(unit);
  }

  @override
  Future<void> startAutomaticChecks() async {}

  @override
  Future<Result<void>> applyManualOnlyUpdateMode() async {
    updateNotificationsEnabled = false;
    automaticSilentUpdatesEnabled = false;
    return const Success(unit);
  }

  bool hasPendingDownloadedUpdateValue = false;

  @override
  Future<bool> get hasPendingDownloadedUpdate async => hasPendingDownloadedUpdateValue;

  final StreamController<void> _changesController = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changesController.stream;

  Result<void> applyPendingResult = const Success(unit);
  int applyPendingCallCount = 0;
  bool? lastApplyTriggerAppClose;

  @override
  Future<Result<void>> applyPendingSilentUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) async {
    applyPendingCallCount += 1;
    lastApplyTriggerAppClose = triggerAppClose;
    return applyPendingResult;
  }

  @override
  bool hasUpdateAwaitingUserConsent = false;

  int applyAvailableUpdateCallCount = 0;
  String? lastApplyAvailableNoticeTitle;
  String? lastApplyAvailableNoticeBody;
  Result<void> applyAvailableUpdateResult = const Success(unit);

  @override
  Future<Result<void>> applyAvailableUpdate({
    String? noticeTitle,
    String? noticeBody,
  }) async {
    applyAvailableUpdateCallCount += 1;
    lastApplyAvailableNoticeTitle = noticeTitle;
    lastApplyAvailableNoticeBody = noticeBody;
    return applyAvailableUpdateResult;
  }

  void emitChange() {
    _changesController.add(null);
  }

  @override
  Future<void> dispose() async {}
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
    RuntimeDetectionDiagnostics? runtimeDiagnostics,
    IStartupService? startupService,
  }) async {
    getIt.registerSingleton<RuntimeCapabilities>(RuntimeCapabilities.full());
    if (runtimeDiagnostics != null) {
      getIt.registerSingleton<RuntimeDetectionDiagnostics>(runtimeDiagnostics);
    }
    if (startupService != null) {
      getIt.registerSingleton<IStartupService>(startupService);
    }
    getIt.registerSingleton<IAutoUpdateOrchestrator>(orchestrator);

    final startupRepository = StartupPreferencesRepository(
      settingsStore,
      startupService: startupService,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ...buildPresentationInfrastructureProviders(
            capabilities: getIt<RuntimeCapabilities>(),
          ),
          ChangeNotifierProvider<ThemeProvider>(
            create: (_) => ThemeProvider(
              AppPreferencesRepository(
                settingsStore: settingsStore,
                startup: startupRepository,
                updates: UpdatePreferencesRepository(settingsStore: settingsStore),
              ),
            ),
          ),
          ChangeNotifierProvider<SystemSettingsProvider>(
            create: (_) => SystemSettingsProvider(startupRepository),
          ),
          ChangeNotifierProvider<UpdatesSettingsProvider>(
            create: (_) => UpdatesSettingsProvider(
              orchestrator,
              capabilities: getIt<RuntimeCapabilities>(),
              runtimeDiagnostics: runtimeDiagnostics,
            ),
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
    final completer = Completer<Result<ManualCheckOutcome>>();
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      onCheckManual: () => completer.future,
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('updates_check_now_button')));
    await tester.pump();

    expect(find.byKey(const ValueKey('updates_progress_ring')), findsOneWidget);
    expect(find.byKey(const ValueKey('updates_check_now_button')), findsOneWidget);

    completer.complete(const Success(ManualCheckOutcome.noUpdate));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('updates_progress_ring')), findsNothing);
    expect(find.byKey(const ValueKey('updates_check_now_button')), findsOneWidget);
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
        return Failure<ManualCheckOutcome, Exception>(
          domain.ServerFailure.withContext(
            message: 'Update check timed out while waiting for updater completion',
          ),
        );
      },
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('updates_check_now_button')));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.gsSectionUpdates), findsWidgets);
    expect(
      find.textContaining('Update check timed out while waiting for updater completion'),
      findsWidgets,
    );
    expect(find.text(ptL10n.configUpdateTechnicalTitle), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ContentDialog),
        matching: find.text(ptL10n.configCopyUpdateDiagnostics),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text(ptL10n.configUpdateTechnicalTitle));
    await tester.pumpAndSettle();

    expect(find.textContaining('${ptL10n.configUpdateTechnicalProbeRequestUrl}:'), findsOneWidget);
    expect(find.textContaining('https://example.com/appcast.xml?cb=1'), findsWidgets);
    expect(find.textContaining(ptL10n.configUpdateCompletionSourceCompletionTimeout), findsOneWidget);
  });

  testWidgets('shows inline notice when manual check reports no update', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      lastManualDiagnostics: UpdateCheckDiagnostics(
        checkedAt: DateTime(2026, 6, 1, 10, 30),
        configuredFeedUrl: officialAutoUpdateFeedUrl,
        requestedFeedUrl: officialAutoUpdateFeedUrl,
        currentVersion: '1.8.1+1',
        completedAt: DateTime(2026, 6, 1, 10, 31),
        completionSource: UpdateCheckCompletionSource.updateNotAvailable,
        updateAvailable: false,
      ),
      onCheckManual: () async => const Success(ManualCheckOutcome.noUpdate),
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('updates_check_now_button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('updates_check_inline_notice')), findsOneWidget);
    expect(find.text(ptL10n.configUpdatesNotAvailable), findsOneWidget);
    expect(find.text(ptL10n.btnOk), findsNothing);
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
      automaticSilentUpdatesEnabled: false,
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

  testWidgets('manual-only link applies both preferences', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(isAvailable: true);

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('updates_manual_only_mode_link')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(orchestrator.updateNotificationsEnabled, isFalse);
    expect(orchestrator.automaticSilentUpdatesEnabled, isFalse);
    expect(find.byKey(const ValueKey('updates_manual_only_mode_link')), findsNothing);
  });

  testWidgets('shows pending notice when notifications are off and update is staged', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(isAvailable: true)
      ..updateNotificationsEnabled = false
      ..hasPendingDownloadedUpdateValue = true;

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.configUpdatePendingReadyNotice), findsOneWidget);
  });

  testWidgets('toggles update notifications preference', (tester) async {
    bool? capturedValue;
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      onSetUpdateNotificationsEnabled: (value) async {
        capturedValue = value;
        return const Success(unit);
      },
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(find.text(ptL10n.configUpdateNotificationsToggle), findsOneWidget);

    await tester.tap(find.byType(ToggleSwitch).first);
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(capturedValue, isFalse);
    expect(orchestrator.updateNotificationsEnabled, isFalse);
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
        return const Success(SilentUpdateOutcome.noNewVersion);
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

  testWidgets('suppresses automatic failure suffix when update notifications are off', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      updateNotificationsEnabled: false,
      lastAutomaticDiagnostics: UpdateCheckDiagnostics(
        checkedAt: DateTime(2026, 5, 14, 11, 20),
        configuredFeedUrl: officialAutoUpdateFeedUrl,
        requestedFeedUrl: officialAutoUpdateFeedUrl,
        currentVersion: '1.6.7+1',
        completedAt: DateTime(2026, 5, 14, 11, 21),
        completionSource: UpdateCheckCompletionSource.automaticDownloadFailure,
      ),
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(
      find.text('${ptL10n.configLastAutomaticUpdatePrefix}14/05/2026 11:20'),
      findsOneWidget,
    );
    expect(
      find.textContaining(ptL10n.configUpdateCompletionSourceAutomaticDownloadFailure),
      findsNothing,
    );
  });

  testWidgets('manual-only mode shows neutral automatic status despite stale diagnostics', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      updateNotificationsEnabled: false,
      automaticSilentUpdatesEnabled: false,
      lastAutomaticDiagnostics: UpdateCheckDiagnostics(
        checkedAt: DateTime(2026, 5, 14, 11, 20),
        configuredFeedUrl: officialAutoUpdateFeedUrl,
        requestedFeedUrl: officialAutoUpdateFeedUrl,
        currentVersion: '1.6.7+1',
        completedAt: DateTime(2026, 5, 14, 11, 21),
        completionSource: UpdateCheckCompletionSource.automaticDownloadFailure,
      ),
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(
      find.text('${ptL10n.configLastAutomaticUpdatePrefix}${ptL10n.configLastUpdateNever}'),
      findsOneWidget,
    );
    expect(
      find.textContaining(ptL10n.configUpdateCompletionSourceAutomaticDownloadFailure),
      findsNothing,
    );
  });

  testWidgets('copies update diagnostics with runtime detection details', (tester) async {
    String? clipboardPayload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map<dynamic, dynamic>;
          clipboardPayload = args['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final orchestrator = FakeAutoUpdateOrchestrator(isAvailable: true);
    await pumpPage(
      tester,
      orchestrator: orchestrator,
      runtimeDiagnostics: RuntimeDetectionDiagnostics.detected(
        source: RuntimeDetectionSource.rtlGetVersion,
        versionInfo: const WindowsVersionInfo(
          majorVersion: 10,
          minorVersion: 0,
          buildNumber: 26200,
          isServer: false,
          productName: 'Windows 10/11',
        ),
      ),
    );

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('updates_copy_diagnostics_button')));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(clipboardPayload, isNotNull);
    expect(clipboardPayload, contains('Runtime Detection'));
    expect(clipboardPayload, contains('runtime_mode: full'));
    expect(clipboardPayload, contains('detection_source: rtl_get_version'));
    expect(clipboardPayload, contains('version: 10.0.26200'));
    expect(clipboardPayload, contains('is_server: false'));
    expect(clipboardPayload, contains('product_name: Windows 10/11'));
    expect(clipboardPayload, contains(ptL10n.configUpdateTechnicalPreferencesTitle));
    expect(clipboardPayload, contains(ptL10n.configUpdateTechnicalNotificationsEnabled));
    expect(clipboardPayload, contains(ptL10n.configUpdateTechnicalAutomaticSilentEnabled));
  });

  testWidgets('shows SettingsFeedback success modal when startup diagnostic is copied', (tester) async {
    final mockStartup = MockStartupService();
    when(mockStartup.isEnabled).thenAnswer((_) async => const Success(false));
    when(
      mockStartup.ensureLaunchConfiguration,
    ).thenAnswer((_) async => const Success(StartupLaunchConfigurationStatus.needsRepair));
    when(
      mockStartup.buildStartupDiagnosticReport,
    ).thenAnswer((_) async => const Success('Plug Agente startup diagnostic\nscope: user'));

    String? clipboardPayload;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall methodCall) async {
        if (methodCall.method == 'Clipboard.setData') {
          final args = methodCall.arguments as Map<dynamic, dynamic>;
          clipboardPayload = args['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
    });

    final orchestrator = FakeAutoUpdateOrchestrator(isAvailable: true);
    await pumpPage(tester, orchestrator: orchestrator, startupService: mockStartup);

    final provider = tester.element(find.byType(ConfigPage)).read<SystemSettingsProvider>();
    await provider.repairStartupLaunchConfiguration();
    await tester.pumpAndSettle();

    await tester.tap(find.text(ptL10n.gsButtonCopyStartupDiagnostic));
    await tester.pumpAndSettle();

    expect(clipboardPayload, 'Plug Agente startup diagnostic\nscope: user');
    expect(find.byType(ContentDialog), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ContentDialog),
        matching: find.text(ptL10n.gsSectionSystem),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(ContentDialog),
        matching: find.text(ptL10n.configStartupDiagnosticsCopied),
      ),
      findsOneWidget,
    );
  });

  testWidgets('shows error feedback when startup diagnostic copy fails', (tester) async {
    final mockStartup = MockStartupService();
    when(mockStartup.isEnabled).thenAnswer((_) async => const Success(false));
    when(
      mockStartup.ensureLaunchConfiguration,
    ).thenAnswer((_) async => const Success(StartupLaunchConfigurationStatus.needsRepair));
    when(
      mockStartup.buildStartupDiagnosticReport,
    ).thenAnswer((_) async => Failure(Exception('diagnostic build failed')));

    final orchestrator = FakeAutoUpdateOrchestrator(isAvailable: true);
    await pumpPage(tester, orchestrator: orchestrator, startupService: mockStartup);

    final provider = tester.element(find.byType(ConfigPage)).read<SystemSettingsProvider>();
    await provider.repairStartupLaunchConfiguration();
    await tester.pumpAndSettle();

    await tester.tap(find.text(ptL10n.gsButtonCopyStartupDiagnostic));
    await tester.pump();
    await tester.pump(const Duration(seconds: 4));

    expect(find.text(ptL10n.configStartupDiagnosticsCopyFailed), findsOneWidget);
  });

  testWidgets('does not update last check label when manual check times out', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      lastManualDiagnostics: UpdateCheckDiagnostics(
        checkedAt: DateTime(2026, 3, 1, 8),
        configuredFeedUrl: officialAutoUpdateFeedUrl,
        requestedFeedUrl: officialAutoUpdateFeedUrl,
        currentVersion: '1.0.0+1',
        completedAt: DateTime(2026, 3, 1, 8, 1),
        completionSource: UpdateCheckCompletionSource.completionTimeout,
      ),
      onCheckManual: () async => const Success(ManualCheckOutcome.completionTimeout),
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('${ptL10n.configLastUpdatePrefix}01/03/2026 08:00'),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('updates_check_now_button')));
    await tester.pumpAndSettle();

    expect(
      find.textContaining('${ptL10n.configLastUpdatePrefix}01/03/2026 08:00'),
      findsOneWidget,
    );
  });

  testWidgets('refreshes background label when orchestrator emits changes', (tester) async {
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      automaticSilentUpdatesEnabled: false,
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
      find.textContaining('${ptL10n.configLastBackgroundUpdatePrefix}08/05/2026 09:15'),
      findsOneWidget,
    );

    orchestrator.lastBackgroundDiagnostics = UpdateCheckDiagnostics(
      checkedAt: DateTime(2026, 5, 9, 10, 30),
      configuredFeedUrl: officialAutoUpdateFeedUrl,
      requestedFeedUrl: officialAutoUpdateFeedUrl,
      currentVersion: '1.6.0+1',
      completedAt: DateTime(2026, 5, 9, 10, 30, 1),
      completionSource: UpdateCheckCompletionSource.updateNotAvailable,
      updateAvailable: false,
    );
    orchestrator.emitChange();
    await tester.pumpAndSettle();

    expect(
      find.textContaining('${ptL10n.configLastBackgroundUpdatePrefix}09/05/2026 10:30'),
      findsOneWidget,
    );
  });

  testWidgets('hides background label when automatic silent updates are enabled', (tester) async {
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
      find.textContaining(ptL10n.configLastBackgroundUpdatePrefix),
      findsNothing,
    );
  });

  testWidgets('manual check still works when manual-only mode is active', (tester) async {
    var manualCheckCount = 0;
    final orchestrator = FakeAutoUpdateOrchestrator(
      isAvailable: true,
      updateNotificationsEnabled: false,
      automaticSilentUpdatesEnabled: false,
      onCheckManual: () async {
        manualCheckCount += 1;
        return const Success(ManualCheckOutcome.noUpdate);
      },
    );

    await pumpPage(tester, orchestrator: orchestrator);

    await tester.tap(find.text(ptL10n.configTabUpdatesAbout));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('updates_check_now_button')));
    await tester.pumpAndSettle();

    expect(manualCheckCount, 1);
  });
}
