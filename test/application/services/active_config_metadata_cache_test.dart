import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/services/active_config_metadata_cache.dart';
import 'package:plug_agente/application/services/active_config_resolver.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_agent_config_repository.dart';
import 'package:result_dart/result_dart.dart';

class _MockAgentConfigRepository extends Mock implements IAgentConfigRepository {}

class _MockActiveConfigResolver extends Mock implements ActiveConfigResolver {}

Config _testConfig({String id = 'cfg-1'}) {
  final now = DateTime.utc(2026, 6, 11);
  return Config(
    id: id,
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 18 for SQL Server',
    connectionString: 'DSN=test',
    username: 'sa',
    databaseName: 'db',
    host: 'localhost',
    port: 1433,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  group('ActiveConfigMetadataCache', () {
    late _MockAgentConfigRepository repository;
    late DateTime now;
    late ActiveConfigMetadataCache cache;

    setUp(() {
      repository = _MockAgentConfigRepository();
      now = DateTime.utc(2026, 6, 11, 12);
      cache = ActiveConfigMetadataCache(
        legacyRepository: repository,
        clock: () => now,
      );
    });

    test('should reuse cached metadata within TTL', () async {
      when(() => repository.getCurrentConfigMetadata()).thenAnswer(
        (_) async => Success(_testConfig()),
      );

      final first = await cache.resolveMetadata();
      final second = await cache.resolveMetadata();

      expect(first?.id, 'cfg-1');
      expect(second?.id, 'cfg-1');
      verify(() => repository.getCurrentConfigMetadata()).called(1);
    });

    test('should refresh metadata after TTL expires', () async {
      when(() => repository.getCurrentConfigMetadata()).thenAnswer(
        (_) async => Success(_testConfig()),
      );

      await cache.resolveMetadata();
      now = now.add(const Duration(seconds: 6));
      await cache.resolveMetadata();

      verify(() => repository.getCurrentConfigMetadata()).called(2);
    });

    test('invalidate should force next resolve to reload', () async {
      when(() => repository.getCurrentConfigMetadata()).thenAnswer(
        (_) async => Success(_testConfig()),
      );

      await cache.resolveMetadata();
      cache.invalidate();
      await cache.resolveMetadata();

      verify(() => repository.getCurrentConfigMetadata()).called(2);
    });

    test('should not cache failed lookups', () async {
      when(() => repository.getCurrentConfigMetadata()).thenAnswer(
        (_) async => Failure(domain.NotFoundFailure('missing')),
      );

      expect(await cache.resolveMetadata(), isNull);
      expect(await cache.resolveMetadata(), isNull);
      verify(() => repository.getCurrentConfigMetadata()).called(2);
    });

    test('resolveForDatabaseAccess should reuse active config within TTL', () async {
      final resolver = _MockActiveConfigResolver();
      cache = ActiveConfigMetadataCache(
        activeConfigResolver: resolver,
        clock: () => now,
      );
      when(resolver.resolveActiveForDatabaseAccess).thenAnswer(
        (_) async => Success(_testConfig()),
      );

      final first = await cache.resolveForDatabaseAccess();
      final second = await cache.resolveForDatabaseAccess();

      expect(first?.id, 'cfg-1');
      expect(second?.id, 'cfg-1');
      verify(resolver.resolveActiveForDatabaseAccess).called(1);
    });
  });
}
