import 'dart:async';
import 'dart:convert';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/l10n/app_localizations.dart';
import 'package:plug_agente/presentation/providers/updates_settings_provider.dart';
import 'package:plug_agente/presentation/widgets/auto_update_ready_banner.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class _FakeOrchestrator implements IAutoUpdateOrchestrator {
  _FakeOrchestrator({
    bool hasPendingDownloadedUpdate = false,
    this.hasUpdateAwaitingUserConsent = false,
    UpdateCheckDiagnostics? diagnostics,
  }) : hasPendingDownloadedUpdateValue = hasPendingDownloadedUpdate,
       lastAutomaticDiagnostics = diagnostics;

  bool hasPendingDownloadedUpdateValue;

  final _changesController = StreamController<void>.broadcast();

  @override
  Stream<void> get changes => _changesController.stream;

  @override
  bool isAvailable = true;

  @override
  bool automaticSilentUpdatesEnabled = true;

  @override
  bool updateNotificationsEnabled = true;

  @override
  bool isSilentCheckInProgress = false;

  @override
  Future<bool> get hasPendingDownloadedUpdate async => hasPendingDownloadedUpdateValue;

  @override
  bool hasUpdateAwaitingUserConsent;

  @override
  UpdateCheckDiagnostics? lastManualDiagnostics;

  @override
  UpdateCheckDiagnostics? lastBackgroundDiagnostics;

  @override
  UpdateCheckDiagnostics? lastAutomaticDiagnostics;

  int applyPendingCallCount = 0;
  int applyAvailableCallCount = 0;
  Result<void> applyPendingResult = const Success(unit);
  Result<void> applyAvailableResult = const Success(unit);

  @override
  Future<Result<ManualCheckOutcome>> checkManual() async => const Success(ManualCheckOutcome.noUpdate);

  @override
  Future<void> checkInBackground() async {}

  @override
  Future<Result<SilentUpdateOutcome>> checkSilently() async => const Success(SilentUpdateOutcome.noNewVersion);

  @override
  Future<void> initialize() async {}

  @override
  Future<Result<void>> setAutomaticSilentUpdatesEnabled(bool enabled) async {
    automaticSilentUpdatesEnabled = enabled;
    return const Success(unit);
  }

  @override
  Future<Result<void>> setUpdateNotificationsEnabled(bool enabled) async {
    updateNotificationsEnabled = enabled;
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

  @override
  Future<Result<void>> applyPendingSilentUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) async {
    applyPendingCallCount += 1;
    return applyPendingResult;
  }

  @override
  Future<Result<void>> applyAvailableUpdate({
    String? noticeTitle,
    String? noticeBody,
  }) async {
    applyAvailableCallCount += 1;
    return applyAvailableResult;
  }

  @override
  Future<void> dispose() async {}
}

UpdateCheckDiagnostics _diag({
  required UpdateCheckCompletionSource source,
  required bool updateAvailable,
  String? pendingVersion,
}) {
  return UpdateCheckDiagnostics(
    checkedAt: DateTime(2026, 5, 1, 12),
    configuredFeedUrl: 'https://example.com/appcast.xml',
    requestedFeedUrl: 'https://example.com/appcast.xml',
    completionSource: source,
    updateAvailable: updateAvailable,
    pendingVersion: pendingVersion,
  );
}

Future<void> _pumpBanner(
  WidgetTester tester, {
  required _FakeOrchestrator orchestrator,
  IAppSettingsStore? settingsStore,
}) async {
  if (getIt.isRegistered<IAutoUpdateOrchestrator>()) {
    await getIt.unregister<IAutoUpdateOrchestrator>();
  }
  getIt.registerSingleton<IAutoUpdateOrchestrator>(orchestrator);
  if (!getIt.isRegistered<RuntimeCapabilities>()) {
    getIt.registerSingleton<RuntimeCapabilities>(RuntimeCapabilities.full());
  }
  if (settingsStore != null) {
    if (getIt.isRegistered<IAppSettingsStore>()) {
      await getIt.unregister<IAppSettingsStore>();
    }
    getIt.registerSingleton<IAppSettingsStore>(settingsStore);
  }
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => UpdatesSettingsProvider(orchestrator),
        ),
      ],
      child: const FluentApp(
        locale: Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: SizedBox(
          width: 1024,
          height: 200,
          child: AutoUpdateReadyBanner(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() async {
    await getIt.reset();
  });

  tearDown(() async {
    await getIt.reset();
  });

  testWidgets('renders nothing when no update state is active', (tester) async {
    final orchestrator = _FakeOrchestrator();
    await _pumpBanner(tester, orchestrator: orchestrator);

    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('renders nothing when update notifications are disabled', (tester) async {
    final orchestrator = _FakeOrchestrator(
      hasPendingDownloadedUpdate: true,
      diagnostics: _diag(
        source: UpdateCheckCompletionSource.automaticInstallReady,
        updateAvailable: true,
        pendingVersion: '99.0.0+1',
      ),
    )..updateNotificationsEnabled = false;
    await _pumpBanner(tester, orchestrator: orchestrator);

    expect(find.byType(FilledButton), findsNothing);
  });

  testWidgets('renders pending-downloaded banner with download icon', (tester) async {
    final orchestrator = _FakeOrchestrator(
      hasPendingDownloadedUpdate: true,
      diagnostics: _diag(
        source: UpdateCheckCompletionSource.automaticInstallReady,
        updateAvailable: true,
        pendingVersion: '99.0.0+1',
      ),
    );
    await _pumpBanner(tester, orchestrator: orchestrator);

    expect(find.byIcon(FluentIcons.download), findsOneWidget);
    expect(find.text('Install now'), findsOneWidget);
  });

  testWidgets('renders awaiting-user-consent banner with shield icon', (tester) async {
    final orchestrator = _FakeOrchestrator(
      hasUpdateAwaitingUserConsent: true,
      diagnostics: _diag(
        source: UpdateCheckCompletionSource.automaticAwaitingUserConsent,
        updateAvailable: true,
        pendingVersion: '99.0.0+1',
      ),
    );
    await _pumpBanner(tester, orchestrator: orchestrator);

    expect(find.byIcon(FluentIcons.shield_solid), findsOneWidget);
    expect(find.text('Download and install'), findsOneWidget);
  });

  testWidgets('clicking primary button on UAC banner calls applyAvailableUpdate after confirmation', (tester) async {
    final orchestrator = _FakeOrchestrator(
      hasUpdateAwaitingUserConsent: true,
      diagnostics: _diag(
        source: UpdateCheckCompletionSource.automaticAwaitingUserConsent,
        updateAvailable: true,
        pendingVersion: '99.0.0+1',
      ),
    );
    await _pumpBanner(tester, orchestrator: orchestrator);

    await tester.tap(find.text('Download and install').first);
    await tester.pumpAndSettle();

    // Confirm dialog appears with a primary action that triggers the apply.
    expect(find.byType(ContentDialog), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(ContentDialog), matching: find.byType(FilledButton)));
    // ProgressRing keeps animating once apply starts, so pumpAndSettle
    // would time out. A bounded pump is enough to flush the async apply.
    await tester.pump(const Duration(milliseconds: 100));

    expect(orchestrator.applyAvailableCallCount, 1);
    expect(orchestrator.applyPendingCallCount, 0);
  });

  testWidgets('clicking primary button on pending-downloaded banner calls applyPendingSilentUpdate', (tester) async {
    final orchestrator = _FakeOrchestrator(
      hasPendingDownloadedUpdate: true,
      diagnostics: _diag(
        source: UpdateCheckCompletionSource.automaticInstallReady,
        updateAvailable: true,
        pendingVersion: '99.0.0+1',
      ),
    );
    await _pumpBanner(tester, orchestrator: orchestrator);

    await tester.tap(find.text('Install now').first);
    await tester.pumpAndSettle();

    await tester.tap(find.descendant(of: find.byType(ContentDialog), matching: find.byType(FilledButton)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(orchestrator.applyPendingCallCount, 1);
    expect(orchestrator.applyAvailableCallCount, 0);
  });

  testWidgets('persists dismiss state to settings store with TTL', (tester) async {
    final store = InMemoryAppSettingsStore();
    final orchestrator = _FakeOrchestrator(
      hasUpdateAwaitingUserConsent: true,
      diagnostics: _diag(
        source: UpdateCheckCompletionSource.automaticAwaitingUserConsent,
        updateAvailable: true,
        pendingVersion: '99.0.0+1',
      ),
    );
    await _pumpBanner(tester, orchestrator: orchestrator, settingsStore: store);

    await tester.tap(find.text('Later').first);
    await tester.pumpAndSettle();

    final persisted = store.getString(AppSettingsKeys.autoUpdateBannerDismiss);
    expect(persisted, isNotNull);
    final decoded = jsonDecode(persisted!) as Map<String, dynamic>;
    expect(decoded['version'], '99.0.0+1');
    expect(decoded['until'], isA<String>());
    final untilStr = decoded['until'] as String;
    final until = DateTime.parse(untilStr);
    expect(until.isAfter(DateTime.now()), isTrue);
  });

  testWidgets('hydrates dismiss state from store and hides banner within TTL', (tester) async {
    final store = InMemoryAppSettingsStore();
    final until = DateTime.now().add(const Duration(hours: 4));
    await store.setString(
      AppSettingsKeys.autoUpdateBannerDismiss,
      jsonEncode(<String, dynamic>{
        'version': '99.0.0+1',
        'until': until.toIso8601String(),
      }),
    );
    final orchestrator = _FakeOrchestrator(
      hasUpdateAwaitingUserConsent: true,
      diagnostics: _diag(
        source: UpdateCheckCompletionSource.automaticAwaitingUserConsent,
        updateAvailable: true,
        pendingVersion: '99.0.0+1',
      ),
    );
    await _pumpBanner(tester, orchestrator: orchestrator, settingsStore: store);

    expect(find.byIcon(FluentIcons.shield_solid), findsNothing);
  });

  testWidgets('shows banner when persisted TTL has expired', (tester) async {
    final store = InMemoryAppSettingsStore();
    final expiredUntil = DateTime.now().subtract(const Duration(minutes: 1));
    await store.setString(
      AppSettingsKeys.autoUpdateBannerDismiss,
      jsonEncode(<String, dynamic>{
        'version': '99.0.0+1',
        'until': expiredUntil.toIso8601String(),
      }),
    );
    final orchestrator = _FakeOrchestrator(
      hasUpdateAwaitingUserConsent: true,
      diagnostics: _diag(
        source: UpdateCheckCompletionSource.automaticAwaitingUserConsent,
        updateAvailable: true,
        pendingVersion: '99.0.0+1',
      ),
    );
    await _pumpBanner(tester, orchestrator: orchestrator, settingsStore: store);

    expect(find.byIcon(FluentIcons.shield_solid), findsOneWidget);
  });

  // Note: visually verifying the localized InfoBar text in widget
  // tests requires fluent_ui's NavigationView overlay infrastructure
  // (and its auto-dismiss Timer breaks the bare test harness). The
  // error-message mapping is covered by orchestrator unit tests that
  // assert the `outcome` context is preserved on the failure.
}
