import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/services/startup_configuration_session_state.dart';
import 'package:plug_agente/application/use_cases/ensure_startup_launch_configuration_at_boot.dart';
import 'package:plug_agente/core/constants/launch_args_constants.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
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
  });

  test('does not treat unhealthy registry entry as autostart without --autostart arg', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(true);
    when(() => repository.startMinimized).thenReturn(true);
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
    when(() => repository.startMinimized).thenReturn(true);
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
    when(() => repository.startMinimized).thenReturn(true);
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
}
