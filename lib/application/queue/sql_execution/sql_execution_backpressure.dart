import 'package:plug_agente/core/constants/sql_pipeline_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/protocol/rpc_error_code.dart';

final class SqlExecutionBackpressure {
  const SqlExecutionBackpressure._();

  /// Default stride for `queue full` rejection logs.
  ///
  /// Sustained back-pressure produces one rejection per submit attempt, which
  /// floods logs without adding new signal. We log the first rejection and
  /// then every Nth rejection while the queue stays saturated.
  static const int defaultFullRejectionLogStride = 10;

  static bool shouldLogFullRejection({
    required int rejectionCount,
    required int logStride,
  }) {
    // Log the first rejection of an episode and then every Nth rejection while
    // the queue stays saturated. The counter is reset by submit as soon as a
    // submission is accepted, so the next saturation burst starts fresh.
    if (rejectionCount == 1) return true;
    return rejectionCount % logStride == 0;
  }

  static Map<String, dynamic> queueContext({
    required String reason,
    required String? requestId,
    required int queueSize,
    required int maxQueueSize,
    required int activeWorkers,
    required int maxWorkers,
    String? userMessage,
  }) {
    return {
      'reason': reason,
      'rpc_error_code': RpcErrorCode.rateLimited,
      'retryable': true,
      'queue_size': queueSize,
      'max_queue_size': maxQueueSize,
      'active_workers': activeWorkers,
      'max_workers': maxWorkers,
      'request_id': ?requestId,
      'user_message': ?userMessage,
    };
  }

  static domain.ConfigurationFailure queueFullFailure({
    required String? requestId,
    required int queueSize,
    required int maxQueueSize,
    required int activeWorkers,
    required int maxWorkers,
  }) {
    return domain.ConfigurationFailure.withContext(
      message: 'SQL execution queue is full; system is under heavy load',
      context: queueContext(
        reason: SqlPipelineContextConstants.sqlQueueFullReason,
        requestId: requestId,
        queueSize: queueSize,
        maxQueueSize: maxQueueSize,
        activeWorkers: activeWorkers,
        maxWorkers: maxWorkers,
        userMessage: 'O agente esta ocupado executando consultas. Aguarde alguns instantes e tente novamente.',
      ),
    );
  }

  static domain.ConfigurationFailure queueDisposedFailure({
    required String message,
    required String? requestId,
  }) {
    return domain.ConfigurationFailure.withContext(
      message: message,
      context: {
        'reason': SqlPipelineContextConstants.queueDisposedReason,
        'request_id': ?requestId,
        'user_message': 'A fila de execucao SQL foi encerrada. Reconecte o agente e tente novamente.',
      },
    );
  }
}
