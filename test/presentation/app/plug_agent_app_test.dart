import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:plug_agente/application/observability/update_check_diagnostics.dart';
import 'package:plug_agente/application/repositories/app_preferences_repository.dart';
import 'package:plug_agente/application/repositories/i_app_preferences_repository.dart';
import 'package:plug_agente/application/repositories/update_preferences_repository.dart';
import 'package:plug_agente/application/services/manual_check_outcome.dart';
import 'package:plug_agente/application/services/silent_update_outcome.dart';
import 'package:plug_agente/core/di/service_locator.dart';
import 'package:plug_agente/core/routes/app_routes.dart';
import 'package:plug_agente/core/runtime/runtime_capabilities.dart';
import 'package:plug_agente/core/services/i_auto_update_orchestrator.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/infrastructure/repositories/startup_preferences_repository.dart';
import 'package:plug_agente/presentation/app/app.dart';
import 'package:plug_agente/presentation/providers/theme_provider.dart';
import 'package:plug_agente/presentation/providers/updates_settings_provider.dart';
import 'package:provider/provider.dart';
import 'package:result_dart/result_dart.dart';

class _RecordingWindowManager implements IWindowManagerService {
  int showCallCount = 0;

  @override
  Future<void> show() async {
    showCallCount += 1;
  }

  @override
  void setCloseToTray({required bool value}) {}

  @override
  void setMinimizeToTray({required bool value}) {}
}

class _FakeOrchestrator implements IAutoUpdateOrchestrator {
  @override
  bool isAvailable = false;

  @override
  bool automaticSilentUpdatesEnabled = false;

  @override
  bool automaticSilentUpdatesAutoApplyEnabled = true;

  @override
  bool updateNotificationsEnabled = false;

  @override
  bool isSilentCheckInProgress = false;

  @override
  bool hasUpdateAwaitingUserConsent = false;

  @override
  UpdateCheckDiagnostics? lastManualDiagnostics;

  @override
  UpdateCheckDiagnostics? lastBackgroundDiagnostics;

  @override
  UpdateCheckDiagnostics? lastAutomaticDiagnostics;

  @override
  Stream<void> get changes => const Stream<void>.empty();

  @override
  Future<bool> get hasPendingDownloadedUpdate async => false;

  @override
  Future<Result<ManualCheckOutcome>> checkManual() async => const Success(ManualCheckOutcome.noUpdate);

  @override
  Future<void> checkInBackground() async {}

  @override
  Future<Result<SilentUpdateOutcome>> checkSilently() async => const Success(SilentUpdateOutcome.noNewVersion);

  @override
  Future<Result<void>> initialize() async => const Success(unit);

  @override
  Future<Result<void>> setAutomaticSilentUpdatesEnabled(bool enabled) async => const Success(unit);

  @override
  Future<Result<void>> setAutomaticSilentUpdatesAutoApplyEnabled(bool enabled) async {
    automaticSilentUpdatesAutoApplyEnabled = enabled;
    return const Success(unit);
  }

  @override
  Future<Result<void>> setUpdateNotificationsEnabled(bool enabled) async => const Success(unit);

  @override
  Future<Result<void>> applyManualOnlyUpdateMode() async => const Success(unit);

  @override
  Future<void> startAutomaticChecks() async {}

  @override
  Future<Result<void>> applyPendingSilentUpdate({
    String? noticeTitle,
    String? noticeBody,
    bool triggerAppClose = true,
  }) async => const Success(unit);

  @override
  Future<Result<void>> applyAvailableUpdate({
    String? noticeTitle,
    String? noticeBody,
  }) async => const Success(unit);

  @override
  Future<void> dispose() async {}
}

IAppPreferencesRepository createThemePreferences(IAppSettingsStore store) {
  return AppPreferencesRepository(
    settingsStore: store,
    startup: StartupPreferencesRepository(store),
    updates: UpdatePreferencesRepository(settingsStore: store),
  );
}

GoRouter createTestRouter() {
  return GoRouter(
    initialLocation: AppRoutes.dashboard,
    routes: [
      GoRoute(
        path: AppRoutes.dashboard,
        builder: (context, state) => const SizedBox(key: Key('dashboard')),
      ),
      GoRoute(
        path: AppRoutes.agentProfile,
        builder: (context, state) => const SizedBox(key: Key('agent-profile')),
      ),
    ],
  );
}

void main() {
  const runtimeChannel = MethodChannel('plug_agente/runtime');
  const codec = StandardMethodCodec();

  late RuntimeCapabilities capabilities;
  late _RecordingWindowManager windowManager;
  late GoRouter router;

  setUp(() async {
    await getIt.reset();
    capabilities = RuntimeCapabilities.full();
    windowManager = _RecordingWindowManager();
    router = createTestRouter();

    getIt.registerSingleton<IWindowManagerService>(windowManager);
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      runtimeChannel,
      null,
    );
    await getIt.reset();
  });

  Future<void> pumpHarness(WidgetTester tester) async {
    final settingsStore = InMemoryAppSettingsStore();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => ThemeProvider(createThemePreferences(settingsStore)),
          ),
          ChangeNotifierProvider(
            create: (_) => UpdatesSettingsProvider(
              _FakeOrchestrator(),
              capabilities: capabilities,
            ),
          ),
        ],
        child: PlugAgentApp(
          capabilities: capabilities,
          routerOverride: router,
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> deliverDeepLink(String payload) async {
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.handlePlatformMessage(
      runtimeChannel.name,
      codec.encodeMethodCall(MethodCall('deliverDeepLink', payload)),
      (_) {},
    );
  }

  testWidgets('deliverDeepLink navigates router to parsed route', (tester) async {
    await pumpHarness(tester);

    await deliverDeepLink('plugdb://agent-profile');
    await tester.pump();

    expect(router.state.uri.path, AppRoutes.agentProfile);
    expect(windowManager.showCallCount, 1);
  });

  testWidgets('deliverDeepLink ignores invalid payload', (tester) async {
    await pumpHarness(tester);

    await deliverDeepLink('   ');
    await tester.pump();

    expect(router.state.uri.path, AppRoutes.dashboard);
    expect(windowManager.showCallCount, 0);
  });
}
