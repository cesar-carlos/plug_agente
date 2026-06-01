import 'dart:async';

import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_keys.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/presentation/providers/system_settings_error.dart';
import 'package:plug_agente/presentation/providers/system_settings_provider.dart';
import 'package:result_dart/result_dart.dart';

class MockWindowManagerService extends Mock implements IWindowManagerService {}

class MockStartupService extends Mock implements IStartupService {}

class FailingAppSettingsStore extends InMemoryAppSettingsStore {
  FailingAppSettingsStore([super.initialValues]);

  @override
  Future<void> setValue(String key, Object value) {
    throw StateError('settings write failed');
  }
}

void main() {
  late InMemoryAppSettingsStore prefs;
  late MockWindowManagerService mockWindowManager;
  late MockStartupService mockStartupService;

  setUp(() async {
    prefs = InMemoryAppSettingsStore();
    mockWindowManager = MockWindowManagerService();
    mockStartupService = MockStartupService();

    when(
      () => mockStartupService.isEnabled(),
    ).thenAnswer((_) async => const Success(false));
    when(
      () => mockStartupService.openSystemSettings(),
    ).thenAnswer((_) async => const Success(unit));
    when(
      () => mockStartupService.ensureLaunchConfiguration(),
    ).thenAnswer((_) async => const Success(StartupLaunchConfigurationStatus.unchanged));
    when(
      () => mockStartupService.ensureLaunchConfiguration(allowElevation: false),
    ).thenAnswer((_) async => const Success(StartupLaunchConfigurationStatus.unchanged));
  });

  group('SystemSettingsProvider', () {
    test('should load default values when no settings are saved', () async {
      final provider = SystemSettingsProvider(prefs);

      check(provider.startWithWindows).equals(false);
      check(provider.startMinimized).equals(false);
      check(provider.minimizeToTray).equals(true);
      check(provider.closeToTray).equals(true);
    });

    test('should load saved values from settings store', () async {
      await prefs.setBool(AppSettingsKeys.startWithWindows, true);
      await prefs.setBool(AppSettingsKeys.startMinimized, true);
      await prefs.setBool(AppSettingsKeys.minimizeToTray, false);
      await prefs.setBool(AppSettingsKeys.closeToTray, false);

      final provider = SystemSettingsProvider(prefs);

      check(provider.startWithWindows).equals(true);
      check(provider.startMinimized).equals(true);
      check(provider.minimizeToTray).equals(false);
      check(provider.closeToTray).equals(false);
    });

    test(
      'should update startWithWindows and persist to settings store',
      () async {
        when(
          () => mockStartupService.enable(),
        ).thenAnswer((_) async => const Success(unit));

        final provider = SystemSettingsProvider(
          prefs,
          startupService: mockStartupService,
        );

        final outcome = await provider.setStartWithWindows(true);

        check(outcome).equals(StartupChangeOutcome.enabled);
        check(provider.startWithWindows).equals(true);
        check(prefs.getBool(AppSettingsKeys.startWithWindows)).equals(true);
        verify(() => mockStartupService.enable()).called(1);
      },
    );

    test('should disable startup when setStartWithWindows is false', () async {
      when(
        () => mockStartupService.disable(),
      ).thenAnswer((_) async => const Success(unit));

      await prefs.setBool(AppSettingsKeys.startWithWindows, true);
      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      final outcome = await provider.setStartWithWindows(false);

      check(outcome).equals(StartupChangeOutcome.disabled);
      check(provider.startWithWindows).equals(false);
      check(prefs.getBool(AppSettingsKeys.startWithWindows)).equals(false);
      verify(() => mockStartupService.disable()).called(1);
    });

    test('should return null outcome when value is unchanged', () async {
      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      final outcome = await provider.setStartWithWindows(false);

      check(outcome).isNull();
      verifyNever(() => mockStartupService.enable());
      verifyNever(() => mockStartupService.disable());
    });

    test('should not update settings when startup service fails', () async {
      when(() => mockStartupService.enable()).thenAnswer(
        (_) async => const Failure(
          StartupServiceFailure(
            message: 'Failed to enable startup',
          ),
        ),
      );

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      final outcome = await provider.setStartWithWindows(true);

      check(outcome).isNull();
      check(provider.startWithWindows).equals(false);
      check(prefs.getBool(AppSettingsKeys.startWithWindows)).isNull();
    });

    test('should keep Windows startup truth when preference persistence fails after enabling', () async {
      final failingPrefs = FailingAppSettingsStore();
      when(
        () => mockStartupService.enable(),
      ).thenAnswer((_) async => const Success(unit));

      final provider = SystemSettingsProvider(
        failingPrefs,
        startupService: mockStartupService,
      );

      final outcome = await provider.setStartWithWindows(true);

      check(outcome).equals(StartupChangeOutcome.enabled);
      check(provider.startWithWindows).equals(true);
      check(provider.preferenceError).isNotNull();
      check(provider.preferenceError!.code).equals(SystemSettingsErrorCode.settingsPersistenceFailed);
    });

    test(
      'should update startMinimized and persist to settings store',
      () async {
        final provider = SystemSettingsProvider(prefs);

        await provider.setStartMinimized(true);

        check(provider.startMinimized).equals(true);
        check(prefs.getBool(AppSettingsKeys.startMinimized)).equals(true);
      },
    );

    test(
      'should update minimizeToTray and apply to WindowManagerService',
      () async {
        final provider = SystemSettingsProvider(
          prefs,
          windowManagerService: mockWindowManager,
        );

        await provider.setMinimizeToTray(false);

        check(provider.minimizeToTray).equals(false);
        check(prefs.getBool(AppSettingsKeys.minimizeToTray)).equals(false);
        verify(
          () => mockWindowManager.setMinimizeToTray(value: false),
        ).called(1);
      },
    );

    test(
      'should update closeToTray and apply to WindowManagerService',
      () async {
        final provider = SystemSettingsProvider(
          prefs,
          windowManagerService: mockWindowManager,
        );

        await provider.setCloseToTray(false);

        check(provider.closeToTray).equals(false);
        check(prefs.getBool(AppSettingsKeys.closeToTray)).equals(false);
        verify(() => mockWindowManager.setCloseToTray(value: false)).called(1);
      },
    );

    test('should not call WindowManagerService when it is null', () async {
      final provider = SystemSettingsProvider(prefs);

      await provider.setMinimizeToTray(false);
      await provider.setCloseToTray(false);

      check(provider.minimizeToTray).equals(false);
      check(provider.closeToTray).equals(false);
    });

    test('should sync startup status with system on initialization', () async {
      when(
        () => mockStartupService.isEnabled(),
      ).thenAnswer((_) async => const Success(true));

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      check(provider.startWithWindows).equals(true);
      check(prefs.getBool(AppSettingsKeys.startWithWindows)).equals(true);
      verify(() => mockStartupService.ensureLaunchConfiguration(allowElevation: false)).called(1);
    });

    test('should repair startup launch configuration when startup is enabled', () async {
      when(
        () => mockStartupService.isEnabled(),
      ).thenAnswer((_) async => const Success(true));

      SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      verify(() => mockStartupService.ensureLaunchConfiguration(allowElevation: false)).called(1);
    });

    test('should not notify after dispose when startup status sync completes', () async {
      final syncCompleter = Completer<Result<bool>>();
      when(
        () => mockStartupService.isEnabled(),
      ).thenAnswer((_) => syncCompleter.future);

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );
      var notificationCount = 0;
      provider.addListener(() {
        notificationCount += 1;
      });

      provider.dispose();
      syncCompleter.complete(const Success(true));
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      check(notificationCount).equals(0);
      check(provider.startWithWindows).equals(false);
    });

    test(
      'should not update settings when startup status sync fails with error',
      () async {
        when(() => mockStartupService.isEnabled()).thenAnswer(
          (_) async => const Failure(
            StartupServiceFailure(
              message: 'Failed to check startup status',
            ),
          ),
        );

        final provider = SystemSettingsProvider(
          prefs,
          startupService: mockStartupService,
        );

        await Future<void>.delayed(const Duration(milliseconds: 100));

        check(provider.startWithWindows).equals(false);
      },
    );

    test('should set typed error when startup enable fails', () async {
      when(() => mockStartupService.enable()).thenAnswer(
        (_) async => const Failure(
          StartupServiceFailure(
            message: 'Registry access denied',
          ),
        ),
      );

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await provider.setStartWithWindows(true);

      check(provider.lastError).isNotNull();
      check(provider.lastError!.code).equals(SystemSettingsErrorCode.startupToggleFailed);
      check(provider.lastError!.startupFailureCode).equals(StartupServiceFailureCode.unknown);
      check(provider.startWithWindows).equals(false);
    });

    test('should run launch configuration repair after enabling startup', () async {
      when(() => mockStartupService.enable()).thenAnswer((_) async => const Success(unit));
      when(
        () => mockStartupService.ensureLaunchConfiguration(),
      ).thenAnswer((_) async => const Success(StartupLaunchConfigurationStatus.repaired));

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await provider.setStartWithWindows(true);

      verify(() => mockStartupService.enable()).called(1);
      verify(() => mockStartupService.ensureLaunchConfiguration()).called(1);
      check(provider.startWithWindows).equals(true);
    });

    test('should expose warning notice when automatic startup launch repair fails', () async {
      when(
        () => mockStartupService.isEnabled(),
      ).thenAnswer((_) async => const Success(true));
      when(() => mockStartupService.ensureLaunchConfiguration(allowElevation: false)).thenAnswer(
        (_) async => const Failure(
          StartupServiceFailure(message: 'Missing launch argument'),
        ),
      );

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      check(provider.lastError).isNull();
      check(provider.startupNotice).isNotNull();
      check(provider.startupNotice!.code).equals(SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed);
      check(provider.startupNotice!.startupFailureCode).equals(StartupServiceFailureCode.unknown);
    });

    test('should expose warning notice when automatic startup launch repair throws', () async {
      when(
        () => mockStartupService.isEnabled(),
      ).thenAnswer((_) async => const Success(true));
      when(
        () => mockStartupService.ensureLaunchConfiguration(allowElevation: false),
      ).thenThrow(StateError('repair failed unexpectedly'));

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      check(provider.lastError).isNull();
      check(provider.startupNotice).isNotNull();
      check(provider.startupNotice!.code).equals(SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed);
      check(provider.startupNotice!.detail).isNull();
    });

    test('should expose repaired notice when automatic startup launch repair succeeds', () async {
      when(
        () => mockStartupService.isEnabled(),
      ).thenAnswer((_) async => const Success(true));
      when(
        () => mockStartupService.ensureLaunchConfiguration(allowElevation: false),
      ).thenAnswer((_) async => const Success(StartupLaunchConfigurationStatus.repaired));

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      check(provider.startupNotice).isNotNull();
      check(provider.startupNotice!.code).equals(SystemSettingsNoticeCode.startupLaunchConfigurationRepaired);
    });

    test('should expose repair notice without elevating during automatic startup validation', () async {
      when(
        () => mockStartupService.isEnabled(),
      ).thenAnswer((_) async => const Success(true));
      when(
        () => mockStartupService.ensureLaunchConfiguration(allowElevation: false),
      ).thenAnswer((_) async => const Success(StartupLaunchConfigurationStatus.needsRepair));

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await Future<void>.delayed(const Duration(milliseconds: 100));

      check(provider.startupNotice).isNotNull();
      check(provider.startupNotice!.code).equals(SystemSettingsNoticeCode.startupLaunchConfigurationRepairFailed);
      verifyNever(() => mockStartupService.ensureLaunchConfiguration());
    });

    test('should repair startup launch configuration on demand', () async {
      when(
        () => mockStartupService.ensureLaunchConfiguration(),
      ).thenAnswer((_) async => const Success(StartupLaunchConfigurationStatus.repaired));

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await provider.repairStartupLaunchConfiguration();

      check(provider.startupNotice).isNotNull();
      check(provider.startupNotice!.code).equals(SystemSettingsNoticeCode.startupLaunchConfigurationRepaired);
    });

    test('should clear notice when startup launch repair finds healthy configuration', () async {
      when(
        () => mockStartupService.ensureLaunchConfiguration(),
      ).thenAnswer((_) async => const Success(StartupLaunchConfigurationStatus.unchanged));

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await provider.repairStartupLaunchConfiguration();

      check(provider.startupNotice).isNull();
    });

    test('should keep startMinimized unchanged when persistence fails', () async {
      final failingPrefs = FailingAppSettingsStore();
      final provider = SystemSettingsProvider(failingPrefs);

      await provider.setStartMinimized(true);

      check(provider.startMinimized).equals(false);
      check(provider.preferenceError).isNotNull();
      check(provider.preferenceError!.code).equals(SystemSettingsErrorCode.settingsPersistenceFailed);
    });

    test('should not apply minimizeToTray runtime change when persistence fails', () async {
      final failingPrefs = FailingAppSettingsStore();
      final provider = SystemSettingsProvider(
        failingPrefs,
        windowManagerService: mockWindowManager,
      );

      await provider.setMinimizeToTray(false);

      check(provider.minimizeToTray).equals(true);
      verifyNever(() => mockWindowManager.setMinimizeToTray(value: false));
      check(provider.preferenceError!.code).equals(SystemSettingsErrorCode.settingsPersistenceFailed);
    });

    test('should expose detail=null when failure is not StartupServiceFailure', () async {
      when(() => mockStartupService.enable()).thenAnswer(
        (_) async => Failure(Exception('generic')),
      );

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await provider.setStartWithWindows(true);

      check(provider.lastError).isNotNull();
      check(provider.startupError).isNotNull();
      check(provider.lastError!.code).equals(SystemSettingsErrorCode.startupToggleFailed);
      check(provider.lastError!.detail).isNull();
    });

    test('should clear error when clearError is called', () async {
      when(() => mockStartupService.enable()).thenAnswer(
        (_) async => const Failure(
          StartupServiceFailure(message: 'Test error'),
        ),
      );

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await provider.setStartWithWindows(true);
      check(provider.lastError).isNotNull();

      provider.clearError();
      check(provider.lastError).isNull();
    });

    test('should set startupServiceUnavailable when service is null', () async {
      final provider = SystemSettingsProvider(prefs);

      await provider.openStartupSettings();

      check(provider.lastError).isNotNull();
      check(provider.startupError).isNotNull();
      check(provider.lastError!.code).equals(SystemSettingsErrorCode.startupServiceUnavailable);
    });

    test('should set startupOpenSystemSettingsFailed when openSystemSettings fails', () async {
      when(() => mockStartupService.openSystemSettings()).thenAnswer(
        (_) async => const Failure(
          StartupServiceFailure(message: 'Cannot launch shell'),
        ),
      );

      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await provider.openStartupSettings();

      check(provider.lastError).isNotNull();
      check(provider.startupError).isNotNull();
      check(provider.lastError!.code).equals(SystemSettingsErrorCode.startupOpenSystemSettingsFailed);
      check(provider.lastError!.detail).isNull();
    });

    test(
      'should call openSystemSettings when openStartupSettings is called',
      () async {
        final provider = SystemSettingsProvider(
          prefs,
          startupService: mockStartupService,
        );

        await provider.openStartupSettings();

        verify(() => mockStartupService.openSystemSettings()).called(1);
      },
    );
  });
}
