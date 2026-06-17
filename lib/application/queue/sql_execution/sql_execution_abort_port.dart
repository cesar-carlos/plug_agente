import 'package:plug_agente/application/queue/sql_execution/sql_execution_queued_request.dart';

final class SqlExecutionAbortPort {
  const SqlExecutionAbortPort._();

  static String? resolveAbortTargetId<T extends Object>({
    required String? requestId,
    required SqlExecutionQueuedRequest<T> request,
  }) {
    final normalizedRequestId = requestId?.trim();
    if (normalizedRequestId != null && normalizedRequestId.isNotEmpty) {
      return normalizedRequestId;
    }
    final queuedRequestId = request.requestId?.trim();
    if (queuedRequestId != null && queuedRequestId.isNotEmpty) {
      return queuedRequestId;
    }
    return null;
  }
}
