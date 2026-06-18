import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/sync_startup_status.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class _MockStartupPreferencesRepository extends Mock implements IStartupPreferencesRepository {}

void main() {
  late _MockStartupPreferencesRepository repository;
  late SyncStartupStatus useCase;

  setUp(() {
    repository = _MockStartupPreferencesRepository();
    useCase = SyncStartupStatus(repository);
  });

  test('skips sync when startup service is unavailable', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(false);

    final result = await useCase();

    expect(result.isSuccess(), isTrue);
    expect(result.getOrNull()?.reconciledStartWithWindows, isNull);
    verifyNever(() => repository.readSystemStartupEnabled());
  });

  test('reconciles stored preference when system state differs', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(false);
    when(() => repository.readSystemStartupEnabled()).thenAnswer(
      (_) async => const Success(true),
    );
    when(() => repository.persistStartWithWindows(true)).thenAnswer(
      (_) async => const Success(unit),
    );
    when(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.unchanged),
    );

    final result = await useCase();

    expect(result.isSuccess(), isTrue);
    expect(result.getOrNull()?.reconciledStartWithWindows, isTrue);
    verify(() => repository.persistStartWithWindows(true)).called(1);
    verify(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).called(1);
  });

  test('returns failure when system startup status cannot be read', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.readSystemStartupEnabled()).thenAnswer(
      (_) async => const Failure(
        StartupServiceFailure(message: 'Registry read failed'),
      ),
    );

    final result = await useCase();

    expect(result.isError(), isTrue);
    expect(result.exceptionOrNull(), isA<StartupServiceFailure>());
  });

  test('validates launch configuration when stored preference is enabled but system is unhealthy', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.startWithWindows).thenReturn(true);
    when(() => repository.readSystemStartupEnabled()).thenAnswer(
      (_) async => const Success(false),
    );
    when(() => repository.persistStartWithWindows(false)).thenAnswer(
      (_) async => const Success(unit),
    );
    when(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.needsRepair),
    );

    final result = await useCase();

    expect(result.isSuccess(), isTrue);
    expect(result.getOrNull()?.reconciledStartWithWindows, isFalse);
    verify(
      () => repository.ensureLaunchConfiguration(allowElevation: false),
    ).called(1);
    verify(() => repository.persistStartWithWindows(false)).called(1);
  });
}
