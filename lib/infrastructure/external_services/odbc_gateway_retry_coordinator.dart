import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:plug_agente/domain/repositories/i_retry_manager.dart';
import 'package:plug_agente/infrastructure/external_services/odbc_execution_deadline.dart';
import 'package:result_dart/result_dart.dart';

/// Coordinates ODBC gateway query/non-query retries with optional timeout budgets.
class OdbcGatewayRetryCoordinator {
  const OdbcGatewayRetryCoordinator(this._retryManager);

  final IRetryManager _retryManager;

  Future<Result<T>> executeWithRetryBudget<T extends Object>(
    Future<Result<T>> Function(Duration? remainingTimeout) operation, {
    required int maxAttempts,
    required int initialDelayMs,
    required double backoffMultiplier,
    required Duration? timeout,
    required String stage,
  }) async {
    if (timeout == null) {
      return _retryManager.execute(
        () => operation(null),
        maxAttempts: maxAttempts,
        initialDelayMs: initialDelayMs,
        backoffMultiplier: backoffMultiplier,
      );
    }

    final deadline = DateTime.now().add(timeout);
    var attempts = 0;
    var delayMs = initialDelayMs;
    Result<T>? lastResult;

    while (attempts < maxAttempts) {
      attempts++;
      final remaining = OdbcExecutionDeadline.remainingFromDeadline(deadline);
      if (remaining == null || remaining <= Duration.zero) {
        return Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'SQL execution budget exhausted before retry attempt',
            context: {
              'timeout': true,
              'timeout_stage': 'sql',
              'stage': stage,
              'reason': OdbcContextConstants.stageBudgetExhaustedReason(stage),
            },
          ),
        );
      }

      final result = await operation(remaining);
      if (result.isSuccess()) {
        return result;
      }

      lastResult = result;
      final exception = result.exceptionOrNull();
      if (exception == null ||
          !_retryManager.isTransientFailure(exception) ||
          attempts >= maxAttempts) {
        return result;
      }

      final remainingBeforeDelay =
          OdbcExecutionDeadline.remainingFromDeadline(deadline);
      if (remainingBeforeDelay == null || remainingBeforeDelay <= Duration.zero) {
        return result;
      }

      final requestedDelay = Duration(milliseconds: delayMs);
      final boundedDelay = requestedDelay < remainingBeforeDelay
          ? requestedDelay
          : remainingBeforeDelay;
      await Future<void>.delayed(boundedDelay);
      delayMs = (delayMs * backoffMultiplier).toInt();
    }

    return lastResult ??
        Failure(
          domain.QueryExecutionFailure.withContext(
            message: 'SQL execution failed before retry could start',
            context: {
              'reason': OdbcContextConstants.stageRetryFailedReason(stage),
              'stage': stage,
            },
          ),
        );
  }

  Future<Result<T>> executeQueryWithRetry<T extends Object>(
    Future<Result<T>> Function(Duration? remainingTimeout) operation, {
    Duration? timeout,
    int maxAttempts = 3,
    int initialDelayMs = 500,
    double backoffMultiplier = 2,
    String stage = 'query',
  }) {
    return executeWithRetryBudget(
      operation,
      maxAttempts: maxAttempts,
      initialDelayMs: initialDelayMs,
      backoffMultiplier: backoffMultiplier,
      timeout: timeout,
      stage: stage,
    );
  }
}
