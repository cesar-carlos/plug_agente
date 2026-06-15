import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/protocol/rpc_response.dart';

/// Helpers for ODBC live E2E when ConnectionCircuitBreaker fast-fails RPC calls.
final class OdbcE2eCircuitBreaker {
  OdbcE2eCircuitBreaker._();

  static const int rpcDatabaseConnectionFailedCode = -32106;

  static bool isOpenRpcResponse(RpcResponse response) {
    final error = response.error;
    if (error == null) {
      return false;
    }
    if (error.code != rpcDatabaseConnectionFailedCode) {
      return false;
    }
    final data = error.data;
    if (data is! Map) {
      return false;
    }
    final map = Map<String, dynamic>.from(data);
    final odbcReason = map['odbc_reason']?.toString();
    if (odbcReason == OdbcContextConstants.circuitBreakerOpenReason) {
      return true;
    }
    final technical = map['technical_message']?.toString().toLowerCase() ?? '';
    return technical.contains('circuit breaker');
  }

  static String recoveryHint({
    int resetTimeoutSeconds = 30,
    int failureThreshold = 5,
  }) {
    return 'Circuit breaker aberto após $failureThreshold falhas reais de conexão ODBC. '
        'Aguarde ${resetTimeoutSeconds}s (CIRCUIT_BREAKER_RESET_SEC) ou reinicie o agente '
        'antes de repetir testes que disparam sql.execute via Hub. '
        'Corrija a causa da primeira falha (DSN, HOST:porta, senha, payload.database).';
  }
}
