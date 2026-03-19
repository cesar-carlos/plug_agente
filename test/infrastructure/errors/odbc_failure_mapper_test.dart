import 'package:flutter_test/flutter_test.dart';
import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/infrastructure/errors/odbc_failure_mapper.dart';

void main() {
  group('OdbcFailureMapper', () {
    test(
      'maps authentication errors from SQLSTATE to clear connection failure',
      () {
        final failure = OdbcFailureMapper.mapConnectionError(
          const ConnectionError(
            message: 'Login failed for user sa',
            sqlState: '28000',
            nativeCode: 18456,
          ),
          operation: 'connect',
        );

        expect(failure, isA<ConnectionFailure>());
        expect(failure.context['reason'], 'authentication_failed');
        expect(failure.context['odbc_sql_state'], '28000');
        expect(failure.context['odbc_native_code'], 18456);
        expect(
          failure.context['user_message'],
          contains('Verifique usuario, senha e permissoes'),
        );
      },
    );

    test('maps missing driver from SQLSTATE to configuration failure', () {
      final failure = OdbcFailureMapper.mapConnectionError(
        const ConnectionError(
          message: 'Data source name not found',
          sqlState: 'IM002',
        ),
        operation: 'connect',
      );

      expect(failure, isA<ConfigurationFailure>());
      expect(failure.context['reason'], 'odbc_driver_not_found');
      expect(failure.context['odbc_sql_state'], 'IM002');
    });

    test('maps retryable connection errors from SQLSTATE 08 class', () {
      final failure = OdbcFailureMapper.mapConnectionError(
        const ConnectionError(
          message: 'Communication link failure',
          sqlState: '08S01',
          nativeCode: 10054,
        ),
        operation: 'connect',
      );

      expect(failure, isA<ConnectionFailure>());
      expect(failure.context['reason'], 'server_unreachable');
      expect(failure.context['retryable'], isTrue);
    });

    test(
      'maps 08001 database server not found to server_unreachable, not driver_not_found',
      () {
        final failure = OdbcFailureMapper.mapConnectionError(
          const ConnectionError(
            message: '[Sybase][ODBC Driver][SQL Anywhere]Database server not found',
            sqlState: '08001',
            nativeCode: -100,
          ),
          operation: 'connect',
        );

        expect(failure, isA<ConnectionFailure>());
        expect(failure.context['reason'], 'server_unreachable');
        expect(failure.context['odbc_sql_state'], '08001');
      },
    );

    test('maps pool exhaustion to transient connection failure', () {
      final failure = OdbcFailureMapper.mapPoolError(
        Exception('Pool exhausted: no connections available'),
        operation: 'pool_acquire',
      );

      expect(failure, isA<ConnectionFailure>());
      expect(failure.context['poolExhausted'], isTrue);
      expect(failure.context['retryable'], isTrue);
      expect(failure.context['reason'], 'pool_exhausted');
    });

    test('maps syntax issues from SQLSTATE to validation failure', () {
      final failure = OdbcFailureMapper.mapQueryError(
        const QueryError(
          message: 'Incorrect syntax near FROM',
          sqlState: '42000',
          nativeCode: 156,
        ),
        operation: 'execute_query',
      );

      expect(failure, isA<ValidationFailure>());
      expect(failure.context['operation'], 'sql_validation');
      expect(failure.context['reason'], 'sql_validation_failed');
      expect(failure.context['odbc_sql_state'], '42000');
    });

    test('maps permission denied from SQLSTATE to query failure', () {
      final failure = OdbcFailureMapper.mapQueryError(
        const QueryError(
          message: 'Permission denied on object',
          sqlState: '42501',
        ),
        operation: 'execute_query',
      );

      expect(failure, isA<QueryExecutionFailure>());
      expect(failure.context['reason'], 'sql_permission_denied');
    });

    test('maps transient query errors from SQLSTATE to retryable failure', () {
      final failure = OdbcFailureMapper.mapQueryError(
        const QueryError(
          message: 'Deadlock victim',
          sqlState: '40001',
          nativeCode: 1205,
        ),
        operation: 'execute_query',
      );

      expect(failure, isA<QueryExecutionFailure>());
      expect(failure.context['reason'], 'transient_query_failure');
      expect(failure.context['retryable'], isTrue);
    });

    test('maps cancelled streaming to explicit cancelled reason', () {
      final failure = OdbcFailureMapper.mapStreamingError(
        StateError('stream_cancelled'),
        operation: 'executeQueryStream',
        cancelledByUser: true,
      );

      expect(failure, isA<QueryExecutionFailure>());
      expect(failure.context['reason'], 'query_cancelled');
      expect(
        failure.context['user_message'],
        'A consulta em streaming foi cancelada.',
      );
    });
  });
}
