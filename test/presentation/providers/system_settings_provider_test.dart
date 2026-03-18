import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/presentation/providers/system_settings_provider.dart';
import 'package:result_dart/result_dart.dart';

class MockWindowManagerService extends Mock implements IWindowManagerService {}

class MockStartupService extends Mock implements IStartupService {}

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
      await prefs.setBool('settings.start_with_windows', true);
      await prefs.setBool('settings.start_minimized', true);
      await prefs.setBool('settings.minimize_to_tray', false);
      await prefs.setBool('settings.close_to_tray', false);

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

        await provider.setStartWithWindows(true);

        check(provider.startWithWindows).equals(true);
        check(prefs.getBool('settings.start_with_windows')).equals(true);
        verify(() => mockStartupService.enable()).called(1);
      },
    );

    test('should disable startup when setStartWithWindows is false', () async {
      when(
        () => mockStartupService.disable(),
      ).thenAnswer((_) async => const Success(unit));

      await prefs.setBool('settings.start_with_windows', true);
      final provider = SystemSettingsProvider(
        prefs,
        startupService: mockStartupService,
      );

      await provider.setStartWithWindows(false);

      check(provider.startWithWindows).equals(false);
      check(prefs.getBool('settings.start_with_windows')).equals(false);
      verify(() => mockStartupService.disable()).called(1);
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

      await provider.setStartWithWindows(true);

      check(provider.startWithWindows).equals(false);
      check(prefs.getBool('settings.start_with_windows')).isNull();
    });

    test(
      'should update startMinimized and persist to settings store',
      () async {
        final provider = SystemSettingsProvider(prefs);

        await provider.setStartMinimized(true);

        check(provider.startMinimized).equals(true);
        check(prefs.getBool('settings.start_minimized')).equals(true);
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
        check(prefs.getBool('settings.minimize_to_tray')).equals(false);
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
        check(prefs.getBool('settings.close_to_tray')).equals(false);
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
      check(prefs.getBool('settings.start_with_windows')).equals(true);
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

    test('should set error message when startup enable fails', () async {
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
      check(provider.lastError!).contains('Registry access denied');
      check(provider.startWithWindows).equals(false);
    });

    test('should clear error message when clearError is called', () async {
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
