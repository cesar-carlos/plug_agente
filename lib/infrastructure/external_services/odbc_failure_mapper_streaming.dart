import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/errors.dart';
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_context.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_failure_mapper_query.dart';

/// Maps ODBC streaming query errors to typed [Failure] values.
class OdbcFailureMapperStreaming {
  OdbcFailureMapperStreaming._();

  static Failure map(
    Object error, {
    String? operation,
    Map<String, dynamic> context = const {},
    bool cancelledByUser = false,
  }) {
    final baseContext = OdbcFailureMapperContext.buildBaseContext(error, operation, context);

    if (cancelledByUser) {
      return QueryExecutionFailure.withContext(
        message: 'Streaming query cancelled by user',
        cause: error,
        context: {
          ...baseContext,
          'reason': OdbcContextConstants.executionCancelledReason,
          'rpc_error_code': RpcErrorCode.executionCancelled,
          'user_message': 'The streaming query was cancelled.',
        },
      );
    }

    return OdbcFailureMapperQuery.map(
      error,
      operation: operation,
      context: {
        ...baseContext,
        'streaming': true,
      },
    );
  }
}
