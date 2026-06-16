import 'dart:async';

import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/core/constants/odbc_context_constants.dart';
import 'package:plug_agente/core/utils/pool_semaphore.dart';
import 'package:plug_agente/domain/errors/failures.dart' as domain;
import 'package:result_dart/result_dart.dart';

/// Limits concurrent ODBC connection tests so UI/RPC probes cannot starve SQL workers.
final class OdbcConnectionTestLimiter {
  OdbcConnectionTestLimiter({
    int? maxConcurrent,
    Duration? acquireTimeout,
    PoolSemaphore? semaphore,
  }) : _semaphore =
           semaphore ??
           PoolSemaphore(
             maxConcurrent ?? ConnectionConstants.defaultMaxConcurrentConnectionTests,
           ),
       _acquireTimeout = acquireTimeout ?? ConnectionConstants.connectionTestAcquireTimeout;

  final PoolSemaphore _semaphore;
  final Duration _acquireTimeout;

  Future<Result<T>> run<T extends Object>(Future<Result<T>> Function() action) async {
    try {
      await _semaphore.acquire(timeout: _acquireTimeout);
    } on TimeoutException catch (error) {
      return Failure(
        domain.ConfigurationFailure.withContext(
          message: 'Too many concurrent ODBC connection tests',
          cause: error,
          context: {
            'reason': OdbcContextConstants.connectionTestRateLimitedReason,
            'user_message':
                'Muitos testes de conexão em andamento. Aguarde um momento e tente novamente.',
          },
        ),
      );
    }

    try {
      return await action();
    } finally {
      _semaphore.release();
    }
  }
}
