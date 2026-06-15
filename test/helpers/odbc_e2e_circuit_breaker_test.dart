import 'package:flutter_test/flutter_test.dart';
import 'package:plug_agente/domain/protocol/rpc_error.dart';
import 'package:plug_agente/domain/protocol/rpc_response.dart';

import 'odbc_e2e_circuit_breaker.dart';

void main() {
  group('OdbcE2eCircuitBreaker', () {
    test('detects circuit breaker open RPC error', () {
      final response = RpcResponse.error(
        id: '1',
        error: const RpcError(
          code: OdbcE2eCircuitBreaker.rpcDatabaseConnectionFailedCode,
          message: 'Database connection failed',
          data: {
            'reason': 'database_connection_failed',
            'odbc_reason': 'circuit_breaker_open',
            'technical_message': 'Circuit breaker open for database connection (15s/30s)',
          },
        ),
      );

      expect(OdbcE2eCircuitBreaker.isOpenRpcResponse(response), isTrue);
      expect(
        OdbcE2eCircuitBreaker.recoveryHint(),
        contains('reinicie o agente'),
      );
    });

    test('ignores unrelated RPC errors', () {
      final response = RpcResponse.error(
        id: '1',
        error: const RpcError(
          code: -32000,
          message: 'Other failure',
        ),
      );

      expect(OdbcE2eCircuitBreaker.isOpenRpcResponse(response), isFalse);
    });
  });
}
