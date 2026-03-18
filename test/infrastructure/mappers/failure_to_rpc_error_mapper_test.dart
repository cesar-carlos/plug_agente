import 'package:checks/checks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/mappers/failure_to_rpc_error_mapper.dart';

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
    });

    test('should map QueryExecutionFailure with timeout to queryTimeout', () {
      final failure = QueryExecutionFailure.withContext(
        message: 'Query timed out',
        context: {'timeout': true},
      );

      final rpcError = FailureToRpcErrorMapper.map(failure);

      expect(rpcError.code, equals(RpcErrorCode.queryTimeout));
    });

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
  });
}
