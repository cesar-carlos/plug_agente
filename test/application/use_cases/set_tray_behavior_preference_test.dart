import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/models/startup_preferences_outcomes.dart';
import 'package:plug_agente/application/use_cases/set_tray_behavior_preference.dart';
import 'package:plug_agente/core/services/i_window_manager_service.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_startup_preferences_repository.dart';
import 'package:result_dart/result_dart.dart';

class _MockStartupPreferencesRepository extends Mock
    implements IStartupPreferencesRepository {}

class _MockWindowManagerService extends Mock implements IWindowManagerService {}

void main() {
  late _MockStartupPreferencesRepository repository;
  late _MockWindowManagerService windowManager;
  late SetTrayBehaviorPreference useCase;

  setUp(() {
    repository = _MockStartupPreferencesRepository();
    windowManager = _MockWindowManagerService();
    useCase = SetTrayBehaviorPreference(
      repository,
      windowManagerService: windowManager,
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

  test('returns failure without applying window manager when persistence fails', () async {
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
    verifyNever(() => windowManager.setCloseToTray(value: false));
  });
}
