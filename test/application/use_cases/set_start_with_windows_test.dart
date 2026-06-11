import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/use_cases/set_start_with_windows.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class _MockStartupPreferencesRepository extends Mock implements IStartupPreferencesRepository {}

void main() {
  late _MockStartupPreferencesRepository repository;
  late SetStartWithWindows useCase;

  setUp(() {
    repository = _MockStartupPreferencesRepository();
    useCase = SetStartWithWindows(repository);
  });

  test('enables startup, repairs launch configuration, and persists preference', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.enableSystemStartup()).thenAnswer(
      (_) async => const Success(unit),
    );
    when(() => repository.ensureLaunchConfiguration()).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.repaired),
    );
    when(() => repository.persistStartWithWindows(true)).thenAnswer(
      (_) async => const Success(unit),
    );

    final result = await useCase(true);

    expect(result.isSuccess(), isTrue);
    final outcome = result.getOrNull();
    expect(outcome?.change, StartupChangeOutcome.enabled);
    expect(
      outcome?.launchConfiguration?.type,
      StartupLaunchConfigurationOutcomeType.repaired,
    );
    verify(() => repository.enableSystemStartup()).called(1);
    verify(() => repository.ensureLaunchConfiguration()).called(1);
    verify(() => repository.persistStartWithWindows(true)).called(1);
  });

  test('returns failure when system startup toggle fails', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.enableSystemStartup()).thenAnswer(
      (_) async => const Failure(
        StartupServiceFailure(message: 'Access denied'),
      ),
    );

    final result = await useCase(true);

    expect(result.isError(), isTrue);
    verifyNever(() => repository.persistStartWithWindows(any()));
  });

  test('persists preference when startup service is unavailable', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(false);
    when(() => repository.persistStartWithWindows(true)).thenAnswer(
      (_) async => const Success(unit),
    );

    final result = await useCase(true);

    expect(result.isSuccess(), isTrue);
    expect(result.getOrNull()?.change, StartupChangeOutcome.enabled);
    verifyNever(() => repository.enableSystemStartup());
    verify(() => repository.persistStartWithWindows(true)).called(1);
  });
}
