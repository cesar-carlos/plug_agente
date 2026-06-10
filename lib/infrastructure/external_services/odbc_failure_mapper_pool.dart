import 'package:odbc_fast/odbc_fast.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_context.dart';

/// Maps ODBC connection pool errors to typed [Failure] values.
class OdbcFailureMapperPool {
  OdbcFailureMapperPool._();

  static Failure map(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
  }) {
    final detail = OdbcFailureMapperContext.extractDetail(error);
    final baseContext = OdbcFailureMapperContext.buildBaseContext(error, operation, context);
    final isExhausted = error is ResourceLimitReachedError || _isPoolExhausted(detail);
    final contextReason = context['reason']?.toString();
    final contextRetryable = context['retryable'];
    final contextUserMessage = context['user_message']?.toString();

    return ConnectionFailure.withContext(
      message: isExhausted ? 'ODBC connection pool exhausted' : 'Failed to acquire a connection from the ODBC pool',
      cause: error,
      context: {
        ...baseContext,
        'poolExhausted': isExhausted,
        'retryable': contextRetryable is bool ? contextRetryable : isExhausted,
        'reason':
            contextReason ??
            (isExhausted ? OdbcContextConstants.poolExhaustedReason : OdbcContextConstants.poolErrorReason),
        'user_message':
            contextUserMessage ??
            (isExhausted
                ? 'The agent has no free connections available. Try again in a moment.'
                : 'Could not acquire an available ODBC connection.'),
      },
    );
  }

  static bool _isPoolExhausted(String detail) {
    final normalized = detail.toLowerCase();
    return normalized.contains('pool exhausted') ||
        normalized.contains('no connections available') ||
        normalized.contains('all pooled connections are busy');
  }
}
