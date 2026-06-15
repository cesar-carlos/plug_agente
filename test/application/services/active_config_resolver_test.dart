import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/core/constants/app_constants.dart';
import 'package:plug_agente/core/settings/app_settings_store.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:result_dart/result_dart.dart';

class MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class MockAppSettingsStore extends Mock implements IAppSettingsStore {}

void main() {
  late MockAgentConfigRepository repository;
  late MockAppSettingsStore settingsStore;
  late ActiveConfigResolver resolver;

  final now = DateTime.utc(2025);
  final fullConfig = Config(
    id: 'cfg-1',
    agentId: 'agent-1',
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 17 for SQL Server',
    connectionString: 'DRIVER={ODBC Driver 17 for SQL Server};SERVER=localhost;UID=sa',
    username: 'sa',
    password: 'db-secret',
    databaseName: 'demo',
    host: 'localhost',
    port: 1433,
    createdAt: now,
    updatedAt: now,
  );

  final metadataConfig = fullConfig.copyWith(password: null);

  setUp(() {
    repository = MockAgentConfigRepository();
    settingsStore = MockAppSettingsStore();
    resolver = ActiveConfigResolver(repository, settingsStore);

    when(() => settingsStore.getString(any())).thenReturn(null);
    when(() => settingsStore.setString(any(), any())).thenAnswer((_) async {});
    when(() => settingsStore.remove(any())).thenAnswer((_) async {});
  });

  group('ActiveConfigResolver database access', () {
    test('resolveConfigForQuery loads full config with ODBC credentials', () async {
      when(() => repository.getById('cfg-1')).thenAnswer((_) async => Success(fullConfig));

      final result = await resolver.resolveConfigForQuery('cfg-1');

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().password, 'db-secret');
      verify(() => repository.getById('cfg-1')).called(1);
      verifyNever(() => repository.getByIdMetadata(any()));
    });

    test('resolveActiveConfig loads full active config with ODBC credentials', () async {
      when(() => settingsStore.getString(AppConstants.activeConfigIdSettingsKey)).thenReturn('cfg-1');
      when(() => repository.getById('cfg-1')).thenAnswer((_) async => Success(fullConfig));

      final result = await resolver.resolveActiveConfig();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().password, 'db-secret');
      verify(() => repository.getById('cfg-1')).called(1);
      verifyNever(() => repository.getByIdMetadata(any()));
    });

    test('resolveExplicit with metadataOnly keeps metadata path for profile consumers', () async {
      when(() => repository.getByIdMetadata('cfg-1')).thenAnswer((_) async => Success(metadataConfig));

      final result = await resolver.resolveExplicit('cfg-1', metadataOnly: true);

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().password, isNull);
      verify(() => repository.getByIdMetadata('cfg-1')).called(1);
      verifyNever(() => repository.getById(any()));
    });

    test('resolveActiveForDatabaseAccess falls back to current config with credentials', () async {
      when(() => repository.getCurrentConfig()).thenAnswer((_) async => Success(fullConfig));
      when(() => repository.getById('cfg-1')).thenAnswer((_) async => Success(fullConfig));

      final result = await resolver.resolveActiveForDatabaseAccess();

      expect(result.isSuccess(), isTrue);
      expect(result.getOrThrow().password, 'db-secret');
      verify(() => repository.getCurrentConfig()).called(1);
      verifyNever(() => repository.getCurrentConfigMetadata());
    });

    test('resolveActiveForDatabaseAccess clears stale active id on not found', () async {
      when(() => settingsStore.getString(AppConstants.activeConfigIdSettingsKey)).thenReturn('missing');
      when(() => repository.getById('missing')).thenAnswer(
        (_) async => Failure(domain.NotFoundFailure('Config not found')),
      );
      when(() => repository.getById('cfg-1')).thenAnswer((_) async => Success(fullConfig));
      when(() => repository.getCurrentConfig()).thenAnswer((_) async => Success(fullConfig));

      final result = await resolver.resolveActiveForDatabaseAccess();

      expect(result.isSuccess(), isTrue);
      verify(() => settingsStore.remove(AppConstants.activeConfigIdSettingsKey)).called(1);
      verify(() => settingsStore.setString(AppConstants.activeConfigIdSettingsKey, 'cfg-1')).called(1);
    });
  });
}
