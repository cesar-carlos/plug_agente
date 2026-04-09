import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/application/mappers/failure_to_rpc_error_mapper.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';

void main() {
  group('FailureToRpcErrorMapper', () {
    test('should map ValidationFailure to invalidParams', () {
      final failure = ValidationFailure('Invalid input');

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(rpcError.code, equals(RpcErrorCode.invalidParams));
      expect(rpcError.message, equals('Invalid params'));
      expect(rpcError.data, isNotNull);
      expect(data['detail'], equals('Invalid input'));
      expect(data['reason'], equals('invalid_params'));
      expect(data['category'], equals('validation'));
      expect(data['recoverable'], isTrue);
      expect(data['retryable'], isFalse);
      expect(data['user_message'], isA<String>());
      expect(data['technical_message'], equals('Invalid input'));
      expect(data['correlation_id'], isA<String>());
      expect(data['timestamp'], isA<String>());
    });

    test(
      'should map ValidationFailure with SQL context to sqlValidationFailed',
      () {
        final failure = ValidationFailure.withContext(
          message: 'SQL syntax error',
          context: {'operation': 'sql_validation'},
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);

        expect(rpcError.code, equals(RpcErrorCode.sqlValidationFailed));
      },
    );

    test('should map QueryExecutionFailure to sqlExecutionFailed', () {
      final failure = QueryExecutionFailure('Query failed');

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.sqlExecutionFailed));
      expect(rpcError.message, equals('SQL execution failed'));
      final data = rpcError.data as Map<String, dynamic>;
      expect(data['recoverable'], isFalse);
    });

    test('should map QueryExecutionFailure with timeout to queryTimeout', () {
      final failure = QueryExecutionFailure.withContext(
        message: 'Query timed out',
        context: {'timeout': true},
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.queryTimeout));
      final data = rpcError.data as Map<String, dynamic>;
      expect(data['retryable'], isTrue);
    });

    test(
      'should map QueryExecutionFailure with connectionFailed to databaseConnectionFailed',
      () {
        final failure = QueryExecutionFailure.withContext(
          message: 'Communication link failure',
          context: {
            'connectionFailed': true,
            'reason': 'connection_lost_during_query',
          },
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);

        expect(rpcError.code, equals(RpcErrorCode.databaseConnectionFailed));
        final data = rpcError.data as Map<String, dynamic>;
        expect(data['reason'], equals('database_connection_failed'));
        expect(data['odbc_reason'], equals('connection_lost_during_query'));
        expect(
          data['type'],
          equals('https://plugdb.dev/problems/database-error'),
        );
      },
    );

    test(
      'should map QueryExecutionFailure transaction context to transactionFailed',
      () {
        final failure = QueryExecutionFailure.withContext(
          message: 'Transaction aborted',
          context: {'reason': 'transaction_failed'},
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);

        check(rpcError.code).equals(RpcErrorCode.transactionFailed);
      },
    );

    test('should map NetworkFailure to networkError', () {
      final failure = NetworkFailure('Connection lost');

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.networkError));
      final data = rpcError.data as Map<String, dynamic>;
      expect(data['retryable'], isTrue);
      expect(data['reason'], equals('network_error'));
      expect(data['category'], equals('network'));
      expect(data['technical_message'], equals('Connection lost'));
    });

    test('should map CompressionFailure on decompress to decodingFailed', () {
      final failure = CompressionFailure.withContext(
        message: 'Failed to decompress',
        context: {'operation': 'decompress'},
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.decodingFailed));
    });

    test('should map CompressionFailure on compress to compressionFailed', () {
      final failure = CompressionFailure.withContext(
        message: 'Failed to compress',
        context: {'operation': 'compress'},
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.compressionFailed));
    });

    test('should include Problem Details data', () {
      final failure = QueryExecutionFailure.withContext(
        message: 'Query failed',
        context: {'table': 'users', 'operation': 'select'},
      );

      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        instance: 'trace-123',
      );

      final data = rpcError.data as Map<String, dynamic>;
      expect(data['type'], isNotNull);
      expect(data['title'], isNotNull);
      expect(data['status'], isNotNull);
      expect(data['detail'], equals('Query failed'));
      expect(data['instance'], equals('trace-123'));
      expect(data['retryable'], isNotNull);
      expect(data['table'], equals('users'));
    });

    test(
      'should map NetworkFailure with timeout_stage transport when flag on',
      () {
        final failure = NetworkFailure.withContext(
          message: 'Connection timeout',
          context: {'timeout': true, 'timeout_stage': 'transport'},
        );

        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          useTimeoutByStage: true,
        );

        expect(rpcError.code, equals(RpcErrorCode.timeout));
        final data = rpcError.data as Map<String, dynamic>;
        expect(data['reason'], equals('transport_timeout'));
      },
    );

    test('should map NetworkFailure with timeout_stage ack when flag on', () {
      final failure = NetworkFailure.withContext(
        message: 'Ack timeout',
        context: {'timeout': true, 'timeout_stage': 'ack'},
      );

      final rpcError = FailureToRpcErrorMapper.map(
        failure,
        useTimeoutByStage: true,
      );

      expect(rpcError.code, equals(RpcErrorCode.timeout));
      final data = rpcError.data as Map<String, dynamic>;
      expect(data['reason'], equals('ack_timeout'));
    });

    test(
      'should map QueryExecutionFailure with timeout_stage sql when flag on',
      () {
        final failure = QueryExecutionFailure.withContext(
          message: 'Query timed out',
          context: {'timeout_stage': 'sql'},
        );

        final rpcError = FailureToRpcErrorMapper.map(
          failure,
          useTimeoutByStage: true,
        );

        expect(rpcError.code, equals(RpcErrorCode.queryTimeout));
      },
    );

    test('should not override reason when useTimeoutByStage is false', () {
      final failure = NetworkFailure.withContext(
        message: 'Connection timeout',
        context: {'timeout': true, 'timeout_stage': 'transport'},
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.timeout));
      final data = rpcError.data as Map<String, dynamic>;
      expect(data['reason'], equals('timeout'));
    });

    test('should sanitize sensitive data from context', () {
      final failure = DatabaseFailure.withContext(
        message: 'Connection failed',
        context: {
          'host': 'localhost',
          'password': 'secret123',
          'connectionString': 'Server=localhost;Password=secret',
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);

      final data = rpcError.data as Map<String, dynamic>;
      expect(data['host'], equals('localhost'));
      expect(data.containsKey('password'), isFalse);
      expect(data.containsKey('connectionString'), isFalse);
    });

    test(
      'should map ConnectionFailure with poolExhausted to connectionPoolExhausted',
      () {
        final failure = ConnectionFailure.withContext(
          message: 'Pool de conexoes ODBC esgotado',
          context: {
            'poolExhausted': true,
            'reason': 'pool_exhausted',
            'user_message': 'O agente esta sem conexoes livres no momento.',
          },
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);

        expect(rpcError.code, equals(RpcErrorCode.connectionPoolExhausted));
        expect(rpcError.message, equals('Connection pool exhausted'));
        final data = rpcError.data as Map<String, dynamic>;
        expect(data['reason'], equals('connection_pool_exhausted'));
        expect(data['odbc_reason'], equals('pool_exhausted'));
        expect(
          data['type'],
          equals('https://plugdb.dev/problems/database-error'),
        );
        expect(data['user_message'], equals(
          'O agente esta sem conexoes livres no momento.',
        ));
      },
    );

    test(
      'should map ConnectionFailure ODBC to databaseConnectionFailed with odbc_reason',
      () {
        final failure = ConnectionFailure.withContext(
          message: 'Nao foi possivel alcancar o servidor de banco de dados',
          context: {
            'connectionFailed': true,
            'reason': 'server_unreachable',
            'user_message':
                'Nao foi possivel conectar ao servidor do banco. Verifique host, porta, VPN.',
          },
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);

        expect(rpcError.code, equals(RpcErrorCode.databaseConnectionFailed));
        expect(rpcError.message, equals('Database connection failed'));
        final data = rpcError.data as Map<String, dynamic>;
        expect(data['reason'], equals('database_connection_failed'));
        expect(data['odbc_reason'], equals('server_unreachable'));
        expect(
          data['type'],
          equals('https://plugdb.dev/problems/database-error'),
        );
        expect(
          data['user_message'],
          equals(
            'Nao foi possivel conectar ao servidor do banco. Verifique host, porta, VPN.',
          ),
        );
      },
    );

    test(
      'should map bare ConnectionFailure to databaseConnectionFailed',
      () {
        final failure = ConnectionFailure('Falha desconhecida ao inicializar ODBC');

        final rpcError = FailureToRpcErrorMapper.map(failure);

        expect(rpcError.code, equals(RpcErrorCode.databaseConnectionFailed));
        final data = rpcError.data as Map<String, dynamic>;
        expect(data['reason'], equals('database_connection_failed'));
        expect(data.containsKey('odbc_reason'), isFalse);
      },
    );

    test('should stringify non-string context reason as odbc_reason', () {
      final failure = QueryExecutionFailure.withContext(
        message: 'ODBC error',
        context: {
          'reason': 42,
          'connectionFailed': true,
        },
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);
      final data = rpcError.data as Map<String, dynamic>;

      expect(data['odbc_reason'], equals('42'));
      expect(data['reason'], equals('database_connection_failed'));
    });

    test(
      'should omit odbc_reason when domain reason matches canonical reason',
      () {
        final failure = ConnectionFailure.withContext(
          message: 'Falha ao conectar',
          context: const {
            'connectionFailed': true,
            'reason': 'database_connection_failed',
          },
        );

        final rpcError = FailureToRpcErrorMapper.map(failure);
        final data = rpcError.data as Map<String, dynamic>;

        expect(data['reason'], equals('database_connection_failed'));
        expect(data.containsKey('odbc_reason'), isFalse);
      },
    );
  });
}
