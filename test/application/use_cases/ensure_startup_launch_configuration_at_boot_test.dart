import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/services/startup_configuration_session_state.dart';
import 'package:plug_agente/application/use_cases/ensure_startup_launch_configuration_at_boot.dart';
import 'package:plug_agente/core/constants/launch_args_constants.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/domain/repositories/i_installer_autostart_request_store.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class _MockStartupPreferencesRepository extends Mock implements IStartupPreferencesRepository {}

void main() {
  late _MockStartupPreferencesRepository repository;
  late StartupConfigurationSessionState sessionState;
  late EnsureStartupLaunchConfigurationAtBoot useCase;

  setUp(() {
    repository = _MockStartupPreferencesRepository();
    sessionState = StartupConfigurationSessionState();
    useCase = EnsureStartupLaunchConfigurationAtBoot(
      repository,
      sessionState: sessionState,
    );
    when(() => repository.readStartupDisabledByUser()).thenAnswer(
      (_) async => const Success(false),
    );
  });

  test('does not treat unhealthy registry entry as autostart without --autostart arg', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(true);
    when(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.repaired),
    );

    final outcome = await useCase(launchArgs: const <String>[]);

    expect(outcome.isAutostartLaunch, isFalse);
    verify(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).called(1);
    verifyNever(() => repository.readSystemStartupEnabled());
    final bootCache = sessionState.takeBootLaunchConfiguration();
    expect(bootCache.present, isTrue);
    expect(bootCache.outcome?.type, StartupLaunchConfigurationOutcomeType.repaired);
  });

  test('keeps args-based autostart without registry defensive hint', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(false);
    when(() => repository.readSystemStartupEnabled()).thenAnswer(
      (_) async => const Success(true),
    );
    when(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.unchanged),
    );

    final outcome = await useCase(
      launchArgs: const <String>[LaunchArgsConstants.autostartArg],
    );

    expect(outcome.isAutostartLaunch, isTrue);
    verify(() => repository.readSystemStartupEnabled()).called(1);
    final bootCache = sessionState.takeBootLaunchConfiguration();
    expect(bootCache.present, isTrue);
    expect(bootCache.outcome, isNull);
  });

  test('skips system read when start with Windows preference is already enabled', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(true);
    when(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.unchanged),
    );

    final outcome = await useCase(launchArgs: const <String>[]);

    expect(outcome.isAutostartLaunch, isFalse);
    verifyNever(() => repository.readSystemStartupEnabled());
    verify(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).called(1);
  });

  test('does not validate launch configuration when startup is disabled', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(false);
    when(() => repository.readSystemStartupEnabled()).thenAnswer(
      (_) async => const Success(false),
    );

    final outcome = await useCase(launchArgs: const <String>[]);

    expect(outcome.isAutostartLaunch, isFalse);
    verify(() => repository.readSystemStartupEnabled()).called(1);
    verifyNever(() => repository.ensureLaunchConfiguration(allowElevation: false));
    final bootCache = sessionState.takeBootLaunchConfiguration();
    expect(bootCache.present, isFalse);
  });

  test('skips launch configuration validation when system startup status cannot be read', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(false);
    when(() => repository.readSystemStartupEnabled()).thenAnswer(
      (_) async => Failure(
        StartupServiceFailure(message: 'Registry read failed'),
      ),
    );

    final outcome = await useCase(launchArgs: const <String>[]);

    expect(outcome.isAutostartLaunch, isFalse);
    verify(() => repository.readSystemStartupEnabled()).called(1);
    verifyNever(() => repository.ensureLaunchConfiguration(allowElevation: false));
  });

  test('enables current-user auto-start when installer left a pending request', () async {
    final requestStore = _FakeInstallerAutostartRequestStore(pending: true);
    useCase = EnsureStartupLaunchConfigurationAtBoot(
      repository,
      sessionState: sessionState,
      installerAutostartRequestStore: requestStore,
    );
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(false);
    when(() => repository.enableSystemStartup()).thenAnswer(
      (_) async => const Success(unit),
    );
    when(() => repository.persistStartWithWindows(true)).thenAnswer(
      (_) async => const Success(unit),
    );
    when(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.repaired),
    );

    final outcome = await useCase(launchArgs: const <String>[]);

    expect(outcome.isAutostartLaunch, isFalse);
    expect(requestStore.pending, isFalse);
    verify(() => repository.enableSystemStartup()).called(1);
    verify(() => repository.persistStartWithWindows(true)).called(1);
    verify(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).called(1);
  });

  test('keeps installer request when current-user enable fails', () async {
    final requestStore = _FakeInstallerAutostartRequestStore(pending: true);
    useCase = EnsureStartupLaunchConfigurationAtBoot(
      repository,
      sessionState: sessionState,
      installerAutostartRequestStore: requestStore,
    );
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(false);
    when(() => repository.enableSystemStartup()).thenAnswer(
      (_) async => Failure(
        StartupServiceFailure(message: 'Access denied'),
      ),
    );
    when(() => repository.readSystemStartupEnabled()).thenAnswer(
      (_) async => const Success(false),
    );

    final outcome = await useCase(launchArgs: const <String>[]);

    expect(outcome.isAutostartLaunch, isFalse);
    expect(requestStore.pending, isTrue);
    verifyNever(() => repository.persistStartWithWindows(true));
    verifyNever(() => repository.ensureLaunchConfiguration(allowElevation: false));
  });

  test('keeps installer request when persist fails after current-user enable', () async {
    final requestStore = _FakeInstallerAutostartRequestStore(pending: true);
    useCase = EnsureStartupLaunchConfigurationAtBoot(
      repository,
      sessionState: sessionState,
      installerAutostartRequestStore: requestStore,
    );
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(false);
    when(() => repository.enableSystemStartup()).thenAnswer(
      (_) async => const Success(unit),
    );
    when(() => repository.persistStartWithWindows(true)).thenAnswer(
      (_) async => Failure(
        StartupServiceFailure(message: 'Failed to persist setting'),
      ),
    );
    when(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.repaired),
    );

    final outcome = await useCase(launchArgs: const <String>[]);

    expect(outcome.isAutostartLaunch, isFalse);
    expect(requestStore.pending, isTrue);
    verify(() => repository.enableSystemStartup()).called(1);
    verify(() => repository.persistStartWithWindows(true)).called(1);
  });

  test('applies installer request on --autostart login launch', () async {
    final requestStore = _FakeInstallerAutostartRequestStore(pending: true);
    useCase = EnsureStartupLaunchConfigurationAtBoot(
      repository,
      sessionState: sessionState,
      installerAutostartRequestStore: requestStore,
    );
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(false);
    when(() => repository.enableSystemStartup()).thenAnswer(
      (_) async => const Success(unit),
    );
    when(() => repository.persistStartWithWindows(true)).thenAnswer(
      (_) async => const Success(unit),
    );
    when(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.repaired),
    );

    final outcome = await useCase(
      launchArgs: const <String>[LaunchArgsConstants.autostartArg],
    );

    expect(outcome.isAutostartLaunch, isTrue);
    expect(requestStore.pending, isFalse);
    verify(() => repository.enableSystemStartup()).called(1);
    verify(() => repository.persistStartWithWindows(true)).called(1);
  });

  test('persists startWithWindows=false when Startup Apps disabled the entry', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(true);
    when(() => repository.readStartupDisabledByUser()).thenAnswer(
      (_) async => const Success(true),
    );
    when(() => repository.persistStartWithWindows(false)).thenAnswer(
      (_) async => const Success(unit),
    );

    final outcome = await useCase(launchArgs: const <String>[]);

    expect(outcome.isAutostartLaunch, isFalse);
    verify(() => repository.persistStartWithWindows(false)).called(1);
    verifyNever(() => repository.ensureLaunchConfiguration(allowElevation: false));
    verifyNever(() => repository.enableSystemStartup());
  });

  test('does not treat Startup Apps accessDenied as a user disable at boot', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(true);
    when(() => repository.readStartupDisabledByUser()).thenAnswer(
      (_) async => Failure(
        StartupServiceFailure(
          message: 'Permission denied',
          startupCode: StartupServiceFailureCode.accessDenied,
        ),
      ),
    );
    when(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.unchanged),
    );

    await useCase(launchArgs: const <String>[]);

    verify(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).called(1);
    verifyNever(() => repository.persistStartWithWindows(false));
  });
}

class _FakeInstallerAutostartRequestStore implements IInstallerAutostartRequestStore {
  _FakeInstallerAutostartRequestStore({required this.pending});

  bool pending;

  @override
  Future<bool> hasPendingRequest() async => pending;

  @override
  Future<void> clearPendingRequest() async {
    pending = false;
  }
}
