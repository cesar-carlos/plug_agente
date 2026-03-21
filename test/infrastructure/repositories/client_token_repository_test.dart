import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/domain/entities/client_token_create_request.dart';
import 'package:plug_agente/domain/entities/client_token_list_query.dart';
import 'package:plug_agente/domain/entities/client_token_rule.dart';
import 'package:plug_agente/domain/entities/client_token_summary.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/infrastructure/datasources/client_token_local_data_source.dart';
import 'package:plug_agente/infrastructure/repositories/client_token_repository.dart';

class MockClientTokenLocalDataSource extends Mock
    implements ClientTokenLocalDataSource {}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const ClientTokenCreateRequest(
        clientId: 'fallback-client',
        allTables: false,
        allViews: false,
        allPermissions: false,
        rules: <ClientTokenRule>[],
      ),
    );
    registerFallbackValue(const ClientTokenListQuery());
  });

  late MockClientTokenLocalDataSource mockDataSource;
  late ClientTokenRepository repository;

  setUp(() {
    mockDataSource = MockClientTokenLocalDataSource();
    repository = ClientTokenRepository(mockDataSource);
  });

  group('ClientTokenRepository', () {
    const createRequest = ClientTokenCreateRequest(
      clientId: 'client-a',
      allTables: true,
      allViews: false,
      allPermissions: false,
      rules: <ClientTokenRule>[],
    );

    test(
      'should return Success with opaque token when create succeeds',
      () async {
        when(() => mockDataSource.createToken(createRequest)).thenAnswer(
          (_) async => 'opaque-token',
        );

        final result = await repository.createToken(createRequest);

        expect(result.isSuccess(), isTrue);
        expect(result.getOrNull(), 'opaque-token');
        verify(() => mockDataSource.createToken(createRequest)).called(1);
      },
    );

    test('should return Failure when create throws', () async {
      when(() => mockDataSource.createToken(createRequest)).thenThrow(
        Exception('disk full'),
      );

      final result = await repository.createToken(createRequest);

      expect(result.isError(), isTrue);
      final Object? err = result.exceptionOrNull();
      expect(err, isA<domain.ServerFailure>());
      expect(
        (err! as domain.ServerFailure).message,
        'Failed to create local client token',
      );
    });

    test('should return null when getTokenById throws', () async {
      when(() => mockDataSource.getTokenById('t1')).thenThrow(
        Exception('read failed'),
      );

      final token = await repository.getTokenById('t1');

      expect(token, isNull);
    });

    test(
      'should return ValidationFailure when update target is missing',
      () async {
        when(
          () => mockDataSource.updateToken(
            'missing',
            createRequest,
            expectedVersion: any(named: 'expectedVersion'),
          ),
        ).thenAnswer((_) async => null);

        final result = await repository.updateToken('missing', createRequest);

        expect(result.isError(), isTrue);
        final Object? err = result.exceptionOrNull();
        expect(err, isA<domain.ValidationFailure>());
        expect(
          (err! as domain.ValidationFailure).message,
          'Client token not found for update operation',
        );
      },
    );

    test('should map version conflict to ValidationFailure', () async {
      when(
        () => mockDataSource.updateToken(
          't1',
          createRequest,
          expectedVersion: any(named: 'expectedVersion'),
        ),
      ).thenThrow(
        const ClientTokenVersionConflictException(currentVersion: 3),
      );

      final result = await repository.updateToken(
        't1',
        createRequest,
        expectedVersion: 2,
      );

      expect(result.isError(), isTrue);
      final Object? err = result.exceptionOrNull();
      expect(err, isA<domain.ValidationFailure>());
      expect(
        (err! as domain.ValidationFailure).message,
        'Client token was modified by another operation',
      );
    });

    test('should return Success when revoke marks token revoked', () async {
      when(() => mockDataSource.markTokenRevoked('t1')).thenAnswer(
        (_) async => true,
      );

      final revokeResult = await repository.revokeToken('t1');

      expect(revokeResult.isSuccess(), isTrue);
    });

    test(
      'should return ValidationFailure when revoke finds no token',
      () async {
        when(() => mockDataSource.markTokenRevoked('t1')).thenAnswer(
          (_) async => false,
        );

        final revokeResult = await repository.revokeToken('t1');

        expect(revokeResult.isError(), isTrue);
        expect(revokeResult.exceptionOrNull(), isA<domain.ValidationFailure>());
      },
    );

    test(
      'should return ValidationFailure when delete finds no token',
      () async {
        when(
          () => mockDataSource.deleteToken('t1'),
        ).thenAnswer((_) async => false);

        final deleteResult = await repository.deleteToken('t1');

        expect(deleteResult.isError(), isTrue);
        expect(
          deleteResult.exceptionOrNull(),
          isA<domain.ValidationFailure>(),
        );
      },
    );

    test('should return Success with list when listTokens succeeds', () async {
      const query = ClientTokenListQuery();
      final rows = <ClientTokenSummary>[
        ClientTokenSummary(
          id: 'a',
          clientId: 'c',
          createdAt: DateTime.utc(2026),
          isRevoked: false,
          tokenValue: 'tv',
          allTables: false,
          allViews: false,
          allPermissions: false,
          rules: const <ClientTokenRule>[],
        ),
      ];
      when(() => mockDataSource.listTokens(query: query)).thenAnswer(
        (_) async => rows,
      );

      final listResult = await repository.listTokens(query: query);

      expect(listResult.isSuccess(), isTrue);
      expect(listResult.getOrNull(), rows);
    });
  });
}
