import 'package:plug_agente/core/logger/app_logger.dart';
import 'package:plug_agente/core/logger/log_rate_limiter.dart';
import 'package:plug_agente/core/security/odbc_connection_fingerprint.dart';
import 'package:plug_agente/domain/errors/failures.dart';
import 'package:plug_agente/domain/protocol/rpc_error.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';

/// Records SQL failures returned to the hub without SQL text or parameters.
abstract final class SqlRpcFailureReporter {
  static final LogRateLimiter _limiter = LogRateLimiter();

  static void report({
    required Failure failure,
    required RpcError rpcError,
    required String rpcMethod,
    String? sql,
    int? elapsedMs,
  }) {
    final reason = failure.context['reason']?.toString() ?? failure.code;
    if (!_limiter.shouldLog('${failure.code}:$reason')) {
      return;
    }
    final context = <String, dynamic>{
      'rpc_error_code': rpcError.code,
      'sql_verb': sqlVerb(sql),
      'sql_fingerprint': ?_sqlFingerprint(sql),
      'elapsed_ms': ?elapsedMs,
      'failure_code': failure.code,
      'operation': rpcMethod,
    };
    if (_isWarning(rpcError.code)) {
      AppLogger.warning('[${failure.code}] ${failure.message}', failure.cause, null, context);
      return;
    }
    failure.log(operation: rpcMethod, additionalContext: context);
  }

  static String? _sqlFingerprint(String? sql) {
    if (sql == null || sql.isEmpty) {
      return null;
    }
    return OdbcConnectionFingerprint.hash(sql);
  }

  static String sqlVerb(String? sql) {
    if (sql == null) {
      return 'UNKNOWN';
    }
    final token = sql.trimLeft().split(RegExp(r'\s+')).firstOrNull?.toUpperCase();
    return switch (token) {
      'SELECT' || 'INSERT' || 'UPDATE' || 'DELETE' || 'WITH' || 'MERGE' => token!,
      _ => 'OTHER',
    };
  }

  static bool _isWarning(int code) {
    return code == RpcErrorCode.invalidParams ||
        code == RpcErrorCode.unauthorized ||
        code == RpcErrorCode.sqlValidationFailed ||
        code == RpcErrorCode.rateLimited;
  }
}
