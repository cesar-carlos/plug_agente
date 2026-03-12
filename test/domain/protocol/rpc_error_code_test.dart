import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';

void main() {
  group('RpcErrorCode catalog', () {
    test('should return stable reason and category for known codes', () {
      expect(
        RpcErrorCode.getReason(RpcErrorCode.invalidParams),
        equals('invalid_params'),
      );
      expect(
        RpcErrorCode.getCategory(RpcErrorCode.invalidParams),
        equals('validation'),
      );
      expect(
        RpcErrorCode.getReason(RpcErrorCode.networkError),
        equals('network_error'),
      );
      expect(
        RpcErrorCode.getCategory(RpcErrorCode.networkError),
        equals('network'),
      );
    });

    test('should build mandatory standardized error data fields', () {
      final data = RpcErrorCode.buildErrorData(
        code: RpcErrorCode.sqlExecutionFailed,
        technicalMessage: 'ODBC execution failed',
        correlationId: 'corr-test',
        timestamp: DateTime.utc(2026),
      );

      expect(data['reason'], equals('sql_execution_failed'));
      expect(data['category'], equals('sql'));
      expect(data['retryable'], isFalse);
      expect(data['user_message'], isA<String>());
      expect(data['technical_message'], equals('ODBC execution failed'));
      expect(data['correlation_id'], equals('corr-test'));
      expect(data['timestamp'], equals('2026-01-01T00:00:00.000Z'));
    });

    test('should merge extra data without removing required fields', () {
      final data = RpcErrorCode.buildErrorData(
        code: RpcErrorCode.methodNotFound,
        technicalMessage: 'Method sql.run not found',
        extra: {'method': 'sql.run'},
      );

      expect(data['method'], equals('sql.run'));
      expect(data['reason'], equals('method_not_found'));
      expect(data['category'], equals('validation'));
    });
  });
}
