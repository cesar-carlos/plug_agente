import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/use_cases/set_tray_behavior_preference.dart';
import 'package:plug_agente/core/services/i_tray_service.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class _MockStartupPreferencesRepository extends Mock implements IStartupPreferencesRepository {}

class _MockWindowManagerService extends Mock implements IWindowManagerService {}

class _MockTrayService extends Mock implements ITrayService {}

void main() {
  late _MockStartupPreferencesRepository repository;
  late _MockWindowManagerService windowManager;
  late _MockTrayService trayService;
  late SetTrayBehaviorPreference useCase;

  setUp(() {
    repository = _MockStartupPreferencesRepository();
    windowManager = _MockWindowManagerService();
    trayService = _MockTrayService();
    when(() => trayService.isReady).thenReturn(true);
    when(() => trayService.availability).thenReturn(TrayAvailability.ready);
    when(() => repository.minimizeToTray).thenReturn(true);
    when(() => repository.closeToTray).thenReturn(true);
    when(() => windowManager.setMinimizeToTray(value: any(named: 'value'))).thenAnswer(
      (_) async => const Success(unit),
    );
    when(() => windowManager.setCloseToTray(value: any(named: 'value'))).thenAnswer(
      (_) async => const Success(unit),
    );
    useCase = SetTrayBehaviorPreference(
      repository,
      windowManagerService: windowManager,
      trayService: trayService,
    );
  });

  test('persists minimizeToTray and applies window manager side effect', () async {
    when(() => repository.persistMinimizeToTray(false)).thenAnswer(
      (_) async => const Success(unit),
    );

    final result = await useCase(TrayBehaviorKind.minimizeToTray, false);

    expect(result.isSuccess(), isTrue);
    expect(result.getOrNull(), isFalse);
    verify(() => windowManager.setMinimizeToTray(value: false)).called(1);
  });

  test('persists closeToTray and applies window manager side effect', () async {
    when(() => repository.persistCloseToTray(false)).thenAnswer(
      (_) async => const Success(unit),
    );

    final result = await useCase(TrayBehaviorKind.closeToTray, false);

    expect(result.isSuccess(), isTrue);
    verify(() => windowManager.setCloseToTray(value: false)).called(1);
  });

  test('rolls back window behavior when persistence fails', () async {
    when(() => repository.persistCloseToTray(false)).thenAnswer(
      (_) async => Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Failed to persist setting',
          cause: StateError('write failed'),
        ),
      ),
    );

    final result = await useCase(TrayBehaviorKind.closeToTray, false);

    expect(result.isError(), isTrue);
    verify(() => windowManager.setCloseToTray(value: false)).called(1);
    verify(() => windowManager.setCloseToTray(value: true)).called(1);
  });

  test('returns typed failure without writing when tray is unavailable', () async {
    when(() => trayService.isReady).thenReturn(false);
    when(() => trayService.availability).thenReturn(TrayAvailability.failed);

    final result = await useCase(TrayBehaviorKind.minimizeToTray, false);

    expect(result.isError(), isTrue);
    expect((result.exceptionOrNull()! as domain.Failure).code, 'TRAY_UNAVAILABLE');
    verifyNever(() => repository.persistMinimizeToTray(any()));
  });
}
