import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/ensure_startup_launch_configuration_at_boot.dart';
import 'package:plug_agente/core/constants/launch_args_constants.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class _MockStartupPreferencesRepository extends Mock implements IStartupPreferencesRepository {}

void main() {
  late _MockStartupPreferencesRepository repository;
  late EnsureStartupLaunchConfigurationAtBoot useCase;

  setUp(() {
    repository = _MockStartupPreferencesRepository();
    useCase = EnsureStartupLaunchConfigurationAtBoot(repository);
  });

  test('treats unhealthy registry entry as autostart when start minimized is enabled', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(true);
    when(() => repository.startMinimized).thenReturn(true);
    when(() => repository.readSystemStartupEnabled()).thenAnswer(
      (_) async => const Success(false),
    );
    when(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.needsRepair),
    );
    when(() => repository.hasRegistryEntryMissingAutostartForCurrentExecutable()).thenAnswer(
      (_) async => const Success(true),
    );

    final outcome = await useCase(launchArgs: const <String>[]);

    expect(outcome.isAutostartLaunch, isTrue);
    verify(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).called(1);
    verify(() => repository.hasRegistryEntryMissingAutostartForCurrentExecutable()).called(1);
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
    verifyNever(() => repository.hasRegistryEntryMissingAutostartForCurrentExecutable());
  });
}
