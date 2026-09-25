import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/use_cases/set_start_with_windows.dart';
import 'package:plug_agente/core/services/i_startup_service.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/errors/startup_service_failure.dart';
import 'package:plug_agente/domain/repositories/i_installer_autostart_request_store.dart';
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
    when(() => repository.ensureLaunchConfiguration(allowElevation: false)).thenAnswer(
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
    verify(() => repository.ensureLaunchConfiguration(allowElevation: false)).called(1);
    verify(() => repository.persistStartWithWindows(true)).called(1);
  });

  test('returns failure when system startup toggle fails', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.enableSystemStartup()).thenAnswer(
      (_) async => Failure(
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

  test('returns failure when preference persistence fails after enabling startup', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.enableSystemStartup()).thenAnswer(
      (_) async => const Success(unit),
    );
    when(() => repository.disableSystemStartup()).thenAnswer(
      (_) async => const Success(unit),
    );
    when(() => repository.ensureLaunchConfiguration(allowElevation: false)).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.unchanged),
    );
    when(() => repository.persistStartWithWindows(true)).thenAnswer(
      (_) async => Failure(
        domain.ConfigurationFailure('Failed to persist setting'),
      ),
    );

    final result = await useCase(true);

    expect(result.isError(), isTrue);
    verify(() => repository.enableSystemStartup()).called(1);
    verify(() => repository.persistStartWithWindows(true)).called(1);
    verify(() => repository.disableSystemStartup()).called(1);
  });

  test('rolls back enable when preference persistence fails after disabling startup', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.disableSystemStartup()).thenAnswer(
      (_) async => const Success(unit),
    );
    when(() => repository.enableSystemStartup()).thenAnswer(
      (_) async => const Success(unit),
    );
    when(() => repository.persistStartWithWindows(false)).thenAnswer(
      (_) async => Failure(
        domain.ConfigurationFailure('Failed to persist setting'),
      ),
    );

    final result = await useCase(false);

    expect(result.isError(), isTrue);
    verify(() => repository.disableSystemStartup()).called(1);
    verify(() => repository.persistStartWithWindows(false)).called(1);
    verify(() => repository.enableSystemStartup()).called(1);
  });

  test('returns rollbackFailed when persist and OS rollback both fail', () async {
    when(() => repository.isStartupServiceAvailable).thenReturn(true);
    when(() => repository.enableSystemStartup()).thenAnswer(
      (_) async => const Success(unit),
    );
    when(() => repository.ensureLaunchConfiguration(allowElevation: false)).thenAnswer(
      (_) async => const Success(StartupLaunchConfigurationStatus.unchanged),
    );
    when(() => repository.persistStartWithWindows(true)).thenAnswer(
      (_) async => Failure(
        domain.ConfigurationFailure('Failed to persist setting'),
      ),
    );
    when(() => repository.disableSystemStartup()).thenAnswer(
      (_) async => Failure(
        StartupServiceFailure(message: 'Could not revert registry'),
      ),
    );

    final result = await useCase(true);

    expect(result.isError(), isTrue);
    expect(result.exceptionOrNull(), isA<StartupServiceFailure>());
    expect(
      (result.exceptionOrNull()! as StartupServiceFailure).startupCode,
      StartupServiceFailureCode.rollbackFailed,
    );
    verify(() => repository.disableSystemStartup()).called(1);
  });

  group('installer auto-start request', () {
    late _FakeInstallerAutostartRequestStore requestStore;

    setUp(() {
      requestStore = _FakeInstallerAutostartRequestStore(pending: true);
      useCase = SetStartWithWindows(
        repository,
        installerAutostartRequestStore: requestStore,
      );
      when(() => repository.isStartupServiceAvailable).thenReturn(true);
      when(() => repository.disableSystemStartup()).thenAnswer(
        (_) async => const Success(unit),
      );
    });

    test('clears a pending installer request when the user disables startup', () async {
      when(() => repository.persistStartWithWindows(false)).thenAnswer(
        (_) async => const Success(unit),
      );

      final result = await useCase(false);

      expect(result.isSuccess(), isTrue);
      expect(requestStore.pending, isFalse);
    });

    test('keeps the installer request when persisting the preference fails', () async {
      when(() => repository.enableSystemStartup()).thenAnswer(
        (_) async => const Success(unit),
      );
      when(() => repository.persistStartWithWindows(false)).thenAnswer(
        (_) async => Failure(domain.ConfigurationFailure('Failed to persist setting')),
      );

      final result = await useCase(false);

      expect(result.isError(), isTrue);
      expect(requestStore.pending, isTrue);
    });

    test('still succeeds when the installer request cannot be cleared', () async {
      requestStore.clearError = const FileSystemException('Access denied');
      when(() => repository.persistStartWithWindows(false)).thenAnswer(
        (_) async => const Success(unit),
      );

      final result = await useCase(false);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrNull()?.change, StartupChangeOutcome.disabled);
    });
  });
}

class _FakeInstallerAutostartRequestStore implements IInstallerAutostartRequestStore {
  _FakeInstallerAutostartRequestStore({required this.pending});

  bool pending;
  Exception? clearError;

  @override
  Future<bool> hasPendingRequest() async => pending;

  @override
  Future<void> clearPendingRequest() async {
    final error = clearError;
    if (error != null) {
      throw error;
    }
    pending = false;
  }
}
