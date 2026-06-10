import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';

class MockClientTokenLocalDataSource extends Mock implements ClientTokenLocalDataSource {}

void main() {
  group('ClientTokenRepository', () {
    late MockClientTokenLocalDataSource mockDataSource;
    late ClientTokenRepository repository;

    setUp(() {
      mockDataSource = MockClientTokenLocalDataSource();
      repository = ClientTokenRepository(mockDataSource);
    });

    test('getTokenById returns Success when token exists', () async {
      const tokenId = 'token-1';
      final summary = ClientTokenSummary(
        id: tokenId,
        clientId: 'client-a',
        createdAt: DateTime.utc(2026),
        isRevoked: false,
        allTables: true,
        allViews: false,
        allPermissions: true,
        rules: const [],
      );
      when(() => mockDataSource.getTokenById(tokenId)).thenAnswer((_) async => summary);

      final result = await repository.getTokenById(tokenId);

      expect(result.isSuccess(), isTrue);
      result.fold(
        (loaded) => expect(loaded.id, tokenId),
        (_) => fail('Expected success'),
      );
    });

    test('getTokenById returns NotFoundFailure when token is absent', () async {
      const tokenId = 'missing-token';
      when(() => mockDataSource.getTokenById(tokenId)).thenAnswer((_) async => null);

      final result = await repository.getTokenById(tokenId);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.NotFoundFailure>()),
      );
    });

    test('getTokenById returns ServerFailure on datasource exception', () async {
      const tokenId = 'token-db-error';
      when(() => mockDataSource.getTokenById(tokenId)).thenThrow(Exception('db down'));

      final result = await repository.getTokenById(tokenId);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ServerFailure>()),
      );
    });

    test('getTokenByHash returns Success when token exists', () async {
      const tokenHash = 'hash-abc';
      final summary = ClientTokenSummary(
        id: 'token-2',
        clientId: 'client-b',
        createdAt: DateTime.utc(2026),
        isRevoked: false,
        allTables: false,
        allViews: false,
        allPermissions: false,
        rules: const [],
      );
      when(() => mockDataSource.getTokenByHash(tokenHash)).thenAnswer((_) async => summary);

      final result = await repository.getTokenByHash(tokenHash);

      expect(result.isSuccess(), isTrue);
      result.fold(
        (loaded) => expect(loaded.clientId, 'client-b'),
        (_) => fail('Expected success'),
      );
    });

    test('getTokenByHash returns NotFoundFailure when token is absent', () async {
      const tokenHash = 'hash-missing';
      when(() => mockDataSource.getTokenByHash(tokenHash)).thenAnswer((_) async => null);

      final result = await repository.getTokenByHash(tokenHash);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.NotFoundFailure>()),
      );
    });

    test('getTokenByHash returns ServerFailure on datasource exception', () async {
      const tokenHash = 'hash-db-error';
      when(() => mockDataSource.getTokenByHash(tokenHash)).thenThrow(Exception('db down'));

      final result = await repository.getTokenByHash(tokenHash);

      expect(result.isError(), isTrue);
      result.fold(
        (_) => fail('Expected failure'),
        (failure) => expect(failure, isA<domain.ServerFailure>()),
      );
    });
  });
}
