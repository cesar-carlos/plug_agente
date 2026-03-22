import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';

class MockFeatureFlags extends Mock implements FeatureFlags {}

QueryRequest _baseRequest({
  String query = 'SELECT 1',
  QueryPaginationRequest? pagination,
  SqlHandlingMode sqlHandlingMode = SqlHandlingMode.managed,
  bool expectMultipleResults = false,
  Map<String, dynamic>? parameters,
}) {
  return QueryRequest(
    id: 'r1',
    agentId: 'a1',
    query: query,
    timestamp: DateTime.utc(2026),
    pagination: pagination,
    sqlHandlingMode: sqlHandlingMode,
    expectMultipleResults: expectMultipleResults,
    parameters: parameters,
  );
}

DatabaseConfig _config(DatabaseType type) {
  return DatabaseConfig(
    driverName: 'SQL Server',
    username: 'u',
    password: 'p',
    database: 'd',
    server: 's',
    port: 1433,
    databaseType: type,
  );
}

void main() {
  group('OdbcGatewayQueryPreparation', () {
    group('validatePaginationForDatabase', () {
      test('should return null when there is no pagination', () {
        final failure =
            OdbcGatewayQueryPreparation.validatePaginationForDatabase(
              _baseRequest(),
              DatabaseType.sqlServer,
            );
        expect(failure, isNull);
      });

      test('should reject preserve_sql with managed pagination', () {
        const pagination = QueryPaginationRequest(page: 1, pageSize: 10);
        final failure =
            OdbcGatewayQueryPreparation.validatePaginationForDatabase(
              _baseRequest(
                pagination: pagination,
                sqlHandlingMode: SqlHandlingMode.preserve,
              ),
              DatabaseType.sqlServer,
            );
        expect(failure, isNotNull);
        expect(
          failure!.message,
          contains('preserve_sql cannot be combined'),
        );
      });

      test(
        'should require ORDER BY for SQL Server when pagination is present',
        () {
          const pagination = QueryPaginationRequest(page: 1, pageSize: 10);
          final failure =
              OdbcGatewayQueryPreparation.validatePaginationForDatabase(
                _baseRequest(
                  query: 'SELECT * FROM t',
                  pagination: pagination,
                ),
                DatabaseType.sqlServer,
              );
          expect(failure, isNotNull);
          expect(failure!.message, contains('ORDER BY'));
        },
      );

      test(
        'should allow PostgreSQL pagination without ORDER BY terms',
        () {
          const pagination = QueryPaginationRequest(page: 1, pageSize: 10);
          final failure =
              OdbcGatewayQueryPreparation.validatePaginationForDatabase(
                _baseRequest(
                  query: 'SELECT * FROM t',
                  pagination: pagination,
                ),
                DatabaseType.postgresql,
              );
          expect(failure, isNull);
        },
      );

      test(
        'should require ORDER BY for SQL Anywhere when pagination is present',
        () {
          const pagination = QueryPaginationRequest(page: 1, pageSize: 10);
          final failure =
              OdbcGatewayQueryPreparation.validatePaginationForDatabase(
                _baseRequest(
                  query: 'SELECT * FROM t',
                  pagination: pagination,
                ),
                DatabaseType.sybaseAnywhere,
              );
          expect(failure, isNotNull);
          expect(failure!.message, contains('ORDER BY'));
        },
      );

      test(
        'should reject managed pagination when SQL already has LIMIT',
        () {
          const pagination = QueryPaginationRequest(page: 1, pageSize: 10);
          final failure =
              OdbcGatewayQueryPreparation.validatePaginationForDatabase(
                _baseRequest(
                  query: 'SELECT * FROM t LIMIT 10',
                  pagination: pagination,
                ),
                DatabaseType.postgresql,
              );
          expect(failure, isNotNull);
          expect(failure!.message, contains('LIMIT'));
        },
      );
    });

    group('prepareQueryExecution', () {
      test('should return original SQL when preserve_sql is set', () {
        const pagination = QueryPaginationRequest(page: 1, pageSize: 10);
        final prepared = OdbcGatewayQueryPreparation.prepareQueryExecution(
          _baseRequest(
            pagination: pagination,
            sqlHandlingMode: SqlHandlingMode.preserve,
          ),
          _config(DatabaseType.sqlServer),
        );
        expect(prepared.sql, 'SELECT 1');
      });

      test('should rewrite SQL for offset pagination when managed', () {
        const pagination = QueryPaginationRequest(
          page: 2,
          pageSize: 10,
          orderBy: [
            QueryPaginationOrderTerm(expression: 'id', lookupKey: 'id'),
          ],
        );
        final prepared = OdbcGatewayQueryPreparation.prepareQueryExecution(
          _baseRequest(
            query: 'SELECT * FROM t',
            pagination: pagination,
          ),
          _config(DatabaseType.sqlServer),
        );
        expect(prepared.sql, isNot(equals('SELECT * FROM t')));
        expect(prepared.sql.toUpperCase(), contains('SELECT'));
      });

      test('should use cursor paginated SQL when stable cursor is set', () {
        const orderBy = [
          QueryPaginationOrderTerm(expression: 'id', lookupKey: 'id'),
        ];
        final cursor = const QueryPaginationCursor(
          page: 1,
          pageSize: 10,
          queryHash: 'qh1',
          orderBy: orderBy,
          lastRowValues: <Object>[1],
        ).toToken();
        final pagination = QueryPaginationRequest(
          page: 2,
          pageSize: 10,
          cursor: cursor,
          queryHash: 'qh1',
          orderBy: orderBy,
          lastRowValues: const [1],
        );
        expect(pagination.usesStableCursor, isTrue);
        final prepared = OdbcGatewayQueryPreparation.prepareQueryExecution(
          _baseRequest(
            query: 'SELECT * FROM t',
            pagination: pagination,
          ),
          _config(DatabaseType.sqlServer),
        );
        expect(prepared.sql, isNot(equals('SELECT * FROM t')));
      });
    });

    group('validateQueryExecutionMode', () {
      test('should reject multi-result with named parameters', () {
        const prepared = OdbcPreparedQueryExecution(
          sql: 'SELECT 1; SELECT 2',
          parameters: {'p': 1},
        );
        final failure = OdbcGatewayQueryPreparation.validateQueryExecutionMode(
          _baseRequest(
            query: 'SELECT 1; SELECT 2',
            expectMultipleResults: true,
          ),
          prepared,
        );
        expect(failure, isNotNull);
        expect(failure!.message, contains('named parameters'));
      });

      test('should reject multi-result with pagination', () {
        const pagination = QueryPaginationRequest(page: 1, pageSize: 10);
        final prepared = OdbcGatewayQueryPreparation.prepareQueryExecution(
          _baseRequest(
            query: 'SELECT 1; SELECT 2',
            pagination: pagination,
            expectMultipleResults: true,
            sqlHandlingMode: SqlHandlingMode.preserve,
          ),
          _config(DatabaseType.sqlServer),
        );
        final failure = OdbcGatewayQueryPreparation.validateQueryExecutionMode(
          _baseRequest(
            query: 'SELECT 1; SELECT 2',
            pagination: pagination,
            expectMultipleResults: true,
            sqlHandlingMode: SqlHandlingMode.preserve,
          ),
          prepared,
        );
        expect(failure, isNotNull);
        expect(failure!.message, contains('Multi-result'));
      });
    });

    group('shouldUseMultiResultExecution', () {
      test('should be false when expectMultipleResults is false', () {
        const prepared = OdbcPreparedQueryExecution(
          sql: 'SELECT 1; SELECT 2',
          parameters: null,
        );
        final use = OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
          _baseRequest(),
          prepared,
        );
        expect(use, isFalse);
      });

      test('should be false when pagination is present on the request', () {
        const pagination = QueryPaginationRequest(page: 1, pageSize: 10);
        const prepared = OdbcPreparedQueryExecution(
          sql: 'SELECT 1; SELECT 2',
          parameters: null,
        );
        final use = OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
          _baseRequest(
            query: 'SELECT 1; SELECT 2',
            pagination: pagination,
            expectMultipleResults: true,
            sqlHandlingMode: SqlHandlingMode.preserve,
          ),
          prepared,
        );
        expect(use, isFalse);
      });

      test('should be false when named parameters are present', () {
        const prepared = OdbcPreparedQueryExecution(
          sql: 'SELECT 1',
          parameters: {'x': 1},
        );
        final use = OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
          _baseRequest(expectMultipleResults: true),
          prepared,
        );
        expect(use, isFalse);
      });

      test('should be false when parameters map is non-empty', () {
        const prepared = OdbcPreparedQueryExecution(
          sql: 'SELECT 1; SELECT 2',
          parameters: {'': 0},
        );
        final use = OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
          _baseRequest(expectMultipleResults: true),
          prepared,
        );
        expect(use, isFalse);
      });

      test('should be true when multi-result and no parameters', () {
        const prepared = OdbcPreparedQueryExecution(
          sql: 'SELECT 1; SELECT 2',
          parameters: null,
        );
        final use = OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
          _baseRequest(expectMultipleResults: true),
          prepared,
        );
        expect(use, isTrue);
      });

      test('should be true when parameters is an empty map', () {
        const prepared = OdbcPreparedQueryExecution(
          sql: 'SELECT 1; SELECT 2',
          parameters: <String, dynamic>{},
        );
        final use = OdbcGatewayQueryPreparation.shouldUseMultiResultExecution(
          _baseRequest(expectMultipleResults: true),
          prepared,
        );
        expect(use, isTrue);
      });
    });

    group('maybeLogPaginatedSqlRewrite', () {
      late MockFeatureFlags flags;

      setUp(() {
        flags = MockFeatureFlags();
      });

      test('should return when featureFlags is null', () {
        const pagination = QueryPaginationRequest(
          page: 2,
          pageSize: 10,
          orderBy: [
            QueryPaginationOrderTerm(expression: 'id', lookupKey: 'id'),
          ],
        );
        final prepared = OdbcGatewayQueryPreparation.prepareQueryExecution(
          _baseRequest(query: 'SELECT * FROM t', pagination: pagination),
          _config(DatabaseType.sqlServer),
        );
        expect(
          () => OdbcGatewayQueryPreparation.maybeLogPaginatedSqlRewrite(
            featureFlags: null,
            request: _baseRequest(
              query: 'SELECT * FROM t',
              pagination: pagination,
            ),
            databaseConfig: _config(DatabaseType.sqlServer),
            preparedExecution: prepared,
          ),
          returnsNormally,
        );
      });

      test('should return when debug log flag is disabled', () {
        when(() => flags.enableOdbcPaginatedSqlDebugLog).thenReturn(false);
        const pagination = QueryPaginationRequest(
          page: 2,
          pageSize: 10,
          orderBy: [
            QueryPaginationOrderTerm(expression: 'id', lookupKey: 'id'),
          ],
        );
        final prepared = OdbcGatewayQueryPreparation.prepareQueryExecution(
          _baseRequest(query: 'SELECT * FROM t', pagination: pagination),
          _config(DatabaseType.sqlServer),
        );
        OdbcGatewayQueryPreparation.maybeLogPaginatedSqlRewrite(
          featureFlags: flags,
          request: _baseRequest(
            query: 'SELECT * FROM t',
            pagination: pagination,
          ),
          databaseConfig: _config(DatabaseType.sqlServer),
          preparedExecution: prepared,
        );
        verify(() => flags.enableOdbcPaginatedSqlDebugLog).called(1);
      });

      test('should return when pagination is absent', () {
        when(() => flags.enableOdbcPaginatedSqlDebugLog).thenReturn(true);
        const prepared = OdbcPreparedQueryExecution(
          sql: 'SELECT 1',
          parameters: null,
        );
        OdbcGatewayQueryPreparation.maybeLogPaginatedSqlRewrite(
          featureFlags: flags,
          request: _baseRequest(),
          databaseConfig: _config(DatabaseType.sqlServer),
          preparedExecution: prepared,
        );
      });

      test('should return when preserve_sql is set', () {
        when(() => flags.enableOdbcPaginatedSqlDebugLog).thenReturn(true);
        const pagination = QueryPaginationRequest(page: 1, pageSize: 10);
        final prepared = OdbcGatewayQueryPreparation.prepareQueryExecution(
          _baseRequest(
            pagination: pagination,
            sqlHandlingMode: SqlHandlingMode.preserve,
          ),
          _config(DatabaseType.sqlServer),
        );
        OdbcGatewayQueryPreparation.maybeLogPaginatedSqlRewrite(
          featureFlags: flags,
          request: _baseRequest(
            pagination: pagination,
            sqlHandlingMode: SqlHandlingMode.preserve,
          ),
          databaseConfig: _config(DatabaseType.sqlServer),
          preparedExecution: prepared,
        );
      });

      test('should return when rewritten SQL matches original', () {
        when(() => flags.enableOdbcPaginatedSqlDebugLog).thenReturn(true);
        const pagination = QueryPaginationRequest(page: 1, pageSize: 10);
        OdbcGatewayQueryPreparation.maybeLogPaginatedSqlRewrite(
          featureFlags: flags,
          request: _baseRequest(pagination: pagination),
          databaseConfig: _config(DatabaseType.sqlServer),
          preparedExecution: const OdbcPreparedQueryExecution(
            sql: 'SELECT 1',
            parameters: null,
          ),
        );
      });

      test('should log when flag enabled and SQL was rewritten', () {
        when(() => flags.enableOdbcPaginatedSqlDebugLog).thenReturn(true);
        const pagination = QueryPaginationRequest(
          page: 2,
          pageSize: 10,
          orderBy: [
            QueryPaginationOrderTerm(expression: 'id', lookupKey: 'id'),
          ],
        );
        final prepared = OdbcGatewayQueryPreparation.prepareQueryExecution(
          _baseRequest(query: 'SELECT * FROM t', pagination: pagination),
          _config(DatabaseType.sqlServer),
        );
        expect(prepared.sql.trim(), isNot(equals('SELECT * FROM t')));
        OdbcGatewayQueryPreparation.maybeLogPaginatedSqlRewrite(
          featureFlags: flags,
          request: _baseRequest(
            query: 'SELECT * FROM t',
            pagination: pagination,
          ),
          databaseConfig: _config(DatabaseType.sqlServer),
          preparedExecution: prepared,
        );
      });
    });
  });
}
