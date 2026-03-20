import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/entities/query_pagination.dart';
import 'package:plug_agente/domain/entities/query_request.dart';
import 'package:plug_agente/infrastructure/config/database_config.dart';
import 'package:plug_agente/infrastructure/config/database_type.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_gateway_query_preparation.dart';

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
    });

    group('validateQueryExecutionMode', () {
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
    });
  });
}
