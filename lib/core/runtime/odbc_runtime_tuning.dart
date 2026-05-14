import 'package:plug_agente/core/constants/connection_constants.dart';

final class OdbcRuntimeTuning {
  const OdbcRuntimeTuning({
    required this.poolSize,
    required this.processorCount,
    required this.asyncWorkerCount,
    required this.asyncMaxPendingRequests,
    required this.asyncBackpressureMode,
  });

  factory OdbcRuntimeTuning.forPoolSize({
    required int poolSize,
    required int processorCount,
    String asyncBackpressureMode = 'failFast',
  }) {
    return OdbcRuntimeTuning(
      poolSize: poolSize,
      processorCount: processorCount,
      asyncWorkerCount: ConnectionConstants.odbcAsyncWorkerCountForPoolSize(
        poolSize,
        processorCount,
      ),
      asyncMaxPendingRequests: ConnectionConstants.odbcAsyncMaxPendingRequestsForPoolSize(poolSize),
      asyncBackpressureMode: asyncBackpressureMode,
    );
  }

  final int poolSize;
  final int processorCount;
  final int asyncWorkerCount;
  final int asyncMaxPendingRequests;
  final String asyncBackpressureMode;

  Map<String, Object> toMap() {
    return <String, Object>{
      'pool_size': poolSize,
      'processor_count': processorCount,
      'async_worker_count': asyncWorkerCount,
      'async_max_pending_requests': asyncMaxPendingRequests,
      'async_backpressure_mode': asyncBackpressureMode,
    };
  }
}
