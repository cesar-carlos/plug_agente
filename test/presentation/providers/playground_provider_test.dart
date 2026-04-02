import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/application/use_cases/execute_playground_query.dart';
import 'package:plug_agente/application/use_cases/execute_streaming_query.dart';
import 'package:plug_agente/application/use_cases/test_db_connection.dart';
import 'package:plug_agente/core/constants/app_strings.dart';
import 'package:plug_agente/domain/entities/config.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/domain/entities/query_response.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/presentation/providers/playground_provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

class MockExecutePlaygroundQuery extends Mock
    implements ExecutePlaygroundQuery {}

class MockTestDbConnection extends Mock implements TestDbConnection {}

class MockExecuteStreamingQuery extends Mock implements ExecuteStreamingQuery {}

void main() {
  group('PlaygroundProvider', () {
    late MockExecutePlaygroundQuery mockExecutePlaygroundQuery;
    late MockTestDbConnection mockTestDbConnection;
    late MockExecuteStreamingQuery mockExecuteStreamingQuery;
    late PlaygroundProvider provider;

    setUpAll(() {
      registerFallbackValue(
        const QueryPaginationRequest(page: 1, pageSize: 50),
      );
      registerFallbackValue(SqlHandlingMode.managed);
    });

    setUp(() {
      mockExecutePlaygroundQuery = MockExecutePlaygroundQuery();
      mockTestDbConnection = MockTestDbConnection();
      mockExecuteStreamingQuery = MockExecuteStreamingQuery();
      provider = PlaygroundProvider(
        mockExecutePlaygroundQuery,
        (String cs) => mockTestDbConnection(cs),
        mockExecuteStreamingQuery,
      );
    });

    test(
      'should not invoke execute use case when query is empty',
      () async {
        provider.setQuery('   ');
        await provider.executeQuery(resetPagination: true);
        verifyNever(
          () => mockExecutePlaygroundQuery(
            any(),
            pagination: any(named: 'pagination'),
            sqlHandlingMode: any(named: 'sqlHandlingMode'),
          ),
        );
        expect(provider.error, AppStrings.queryValidationEmpty);
        expect(provider.isLoading, isFalse);
      },
    );

    test('should throttle notifyListeners during streaming chunks', () async {
      var listenerCalls = 0;
      provider.addListener(() {
        listenerCalls++;
      });

      when(
        () => mockExecuteStreamingQuery(any(), any(), any()),
      ).thenAnswer((invocation) async {
        final onChunk =
            invocation.positionalArguments[2]
                as Future<void> Function(List<Map<String, dynamic>>);
        await onChunk([
          {'id': 1},
        ]);
        await onChunk([
          {'id': 2},
        ]);
        await onChunk([
          {'id': 3},
        ]);
        return const rd.Success(rd.unit);
      });

      await provider.executeQueryWithStreaming(
        'SELECT * FROM users',
        'DSN=Test',
      );

      expect(provider.results.length, 3);
      expect(provider.affectedRows, 3);
      expect(listenerCalls, lessThanOrEqualTo(4));
      expect(listenerCalls, greaterThanOrEqualTo(2));
    });

    test(
      'should expose explicit success state for connection status',
      () async {
        final config = _buildConfig();
        when(() => mockTestDbConnection(any())).thenAnswer((_) async {
          return const rd.Success(true);
        });

        await provider.testConnection(config);

        expect(provider.connectionStatus, AppStrings.queryConnectionSuccess);
        expect(provider.isConnectionStatusSuccess, isTrue);
        expect(provider.error, isNull);
      },
    );

    test(
      'should execute paginated query and expose pagination state',
      () async {
        provider.setQuery('SELECT * FROM users');

        when(
          () => mockExecutePlaygroundQuery(
            any(),
            pagination: any(named: 'pagination'),
          ),
        ).thenAnswer((_) async {
          return rd.Success(
            QueryResponse(
              id: 'resp-1',
              requestId: 'req-1',
              agentId: 'agent-1',
              data: const [
                {'id': 1},
                {'id': 2},
              ],
              affectedRows: 2,
              timestamp: DateTime.now(),
              pagination: const QueryPaginationInfo(
                page: 1,
                pageSize: 50,
                returnedRows: 2,
                hasNextPage: true,
                hasPreviousPage: false,
              ),
            ),
          );
        });

        await provider.executeQuery(resetPagination: true);

        expect(provider.results, hasLength(2));
        expect(provider.currentPage, 1);
        expect(provider.pageSize, 50);
        expect(provider.hasNextPage, isTrue);
        expect(provider.hasPagination, isTrue);
      },
    );

    test('should move to next page using current pagination state', () async {
      provider.setQuery('SELECT * FROM users');

      when(
        () => mockExecutePlaygroundQuery(
          any(),
          pagination: any(named: 'pagination'),
        ),
      ).thenAnswer((invocation) async {
        final pagination =
            invocation.namedArguments[#pagination] as QueryPaginationRequest;
        return rd.Success(
          QueryResponse(
            id: 'resp-${pagination.page}',
            requestId: 'req-${pagination.page}',
            agentId: 'agent-1',
            data: [
              {'page': pagination.page},
            ],
            affectedRows: 1,
            timestamp: DateTime.now(),
            pagination: QueryPaginationInfo(
              page: pagination.page,
              pageSize: pagination.pageSize,
              returnedRows: 1,
              hasNextPage: pagination.page == 1,
              hasPreviousPage: pagination.page > 1,
            ),
          ),
        );
      });

      await provider.executeQuery(resetPagination: true);
      await provider.goToNextPage();

      expect(provider.currentPage, 2);
      expect(provider.hasPreviousPage, isTrue);
      expect(provider.results.single['page'], 2);
    });

    test('should expose and switch between multiple result sets', () async {
      provider.setQuery('SELECT 1; SELECT 2;');

      when(
        () => mockExecutePlaygroundQuery(
          any(),
          pagination: any(named: 'pagination'),
        ),
      ).thenAnswer((_) async {
        return rd.Success(
          QueryResponse(
            id: 'resp-1',
            requestId: 'req-1',
            agentId: 'agent-1',
            data: const [
              {'first_value': 1},
            ],
            affectedRows: 1,
            timestamp: DateTime.now(),
            resultSets: const [
              QueryResultSet(
                index: 0,
                rows: [
                  {'first_value': 1},
                ],
                rowCount: 1,
                columnMetadata: [
                  {'name': 'first_value'},
                ],
              ),
              QueryResultSet(
                index: 1,
                rows: [
                  {'second_value': 2},
                ],
                rowCount: 1,
                columnMetadata: [
                  {'name': 'second_value'},
                ],
              ),
            ],
          ),
        );
      });

      await provider.executeQuery(resetPagination: true);

      expect(provider.hasMultipleResultSets, isTrue);
      expect(provider.results.single['first_value'], 1);
      expect(provider.columnMetadata!.single['name'], 'first_value');

      provider.setSelectedResultSetIndex(1);

      expect(provider.selectedResultSetIndex, 1);
      expect(provider.results.single['second_value'], 2);
      expect(provider.columnMetadata!.single['name'], 'second_value');
    });

    test('should notify sync callback when query succeeds', () async {
      final synced = <bool>[];
      final p = PlaygroundProvider(
        mockExecutePlaygroundQuery,
        (String cs) => mockTestDbConnection(cs),
        mockExecuteStreamingQuery,
        syncDbConnectionIndicator: synced.add,
      );
      p.setQuery('SELECT 1');

      when(
        () => mockExecutePlaygroundQuery(
          any(),
          pagination: any(named: 'pagination'),
        ),
      ).thenAnswer(
        (_) async => rd.Success(
          QueryResponse(
            id: 'resp-1',
            requestId: 'req-1',
            agentId: 'agent-1',
            data: const [
              {'x': 1},
            ],
            affectedRows: 1,
            timestamp: DateTime.now(),
          ),
        ),
      );

      await p.executeQuery(resetPagination: true);

      expect(synced, [true]);
    });

    test(
      'should notify sync callback when query fails with connection failure',
      () async {
        final synced = <bool>[];
        final p = PlaygroundProvider(
          mockExecutePlaygroundQuery,
          (String cs) => mockTestDbConnection(cs),
          mockExecuteStreamingQuery,
          syncDbConnectionIndicator: synced.add,
        );
        p.setQuery('SELECT 1');

        when(
          () => mockExecutePlaygroundQuery(
            any(),
            pagination: any(named: 'pagination'),
          ),
        ).thenAnswer(
          (_) async => rd.Failure(
            ConnectionFailure.withContext(
              message: 'ODBC unreachable',
              context: const {'operation': 'test'},
            ),
          ),
        );

        await p.executeQuery(resetPagination: true);

        expect(synced, [false]);
      },
    );
  });
}

Config _buildConfig() {
  final now = DateTime.now();
  return Config(
    id: 'cfg-provider',
    driverName: 'SQL Server',
    odbcDriverName: 'ODBC Driver 17 for SQL Server',
    connectionString: 'DSN=Test',
    username: 'sa',
    databaseName: 'master',
    host: 'localhost',
    port: 1433,
    createdAt: now,
    updatedAt: now,
    agentId: 'agent-1',
  );
}
