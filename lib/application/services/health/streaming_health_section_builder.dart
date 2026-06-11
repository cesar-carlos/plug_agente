import 'package:plug_agente/core/config/feature_flags.dart';
import 'package:plug_agente/domain/repositories/i_streaming_database_gateway.dart';

final class StreamingHealthSectionBuilder {
  const StreamingHealthSectionBuilder({
    IStreamingDatabaseGateway? streamingGateway,
    FeatureFlags? featureFlags,
  }) : _streamingGateway = streamingGateway,
       _featureFlags = featureFlags;

  final IStreamingDatabaseGateway? _streamingGateway;
  final FeatureFlags? _featureFlags;

  Map<String, Object?> build(Map<String, Object?> metrics) {
    final gateway = _streamingGateway;
    final diagnostics = switch (gateway) {
      final IStreamingGatewayDiagnostics streamingDiagnostics => streamingDiagnostics.getStreamingDiagnostics(),
      _ => const <String, Object?>{},
    };
    final dbStreamingFlag = _featureFlags?.enableSocketStreamingFromDb ?? false;
    final chunkStreamingFlag = _featureFlags?.enableSocketStreamingChunks ?? false;
    final effectiveDbStreamingEnabled = gateway != null && dbStreamingFlag;

    return {
      'enabled': effectiveDbStreamingEnabled,
      'gateway_available': diagnostics['enabled'] ?? gateway != null,
      'db_streaming_flag_enabled': dbStreamingFlag,
      'chunk_streaming_flag_enabled': chunkStreamingFlag,
      'auto_db_streaming_policy_enabled': dbStreamingFlag && !chunkStreamingFlag,
      'active_streams': diagnostics['active_streams'] ?? (gateway?.hasActiveStream ?? false ? 1 : 0),
      'direct_limiter_active_count': diagnostics['direct_limiter_active_count'],
      'direct_limiter_max_concurrent': diagnostics['direct_limiter_max_concurrent'],
      'direct_limiter_saturated': diagnostics['direct_limiter_saturated'] ?? false,
      'from_db_responses_total': metrics['rpc_sql_execute_streaming_from_db_response'] ?? 0,
      'auto_from_db_responses_total': metrics['rpc_sql_execute_auto_streaming_from_db_response'] ?? 0,
      'prefer_from_db_responses_total': metrics['rpc_sql_execute_prefer_db_streaming_response'] ?? 0,
      'allowlist_from_db_responses_total': metrics['rpc_sql_execute_allowlist_db_streaming_response'] ?? 0,
      'from_db_skip_total': metrics['rpc_sql_execute_db_streaming_skip'] ?? 0,
      'from_db_skip_reasons': metrics['rpc_sql_execute_db_streaming_skip_reasons'] ?? const <String, int>{},
      'chunked_materialized_responses_total': metrics['rpc_sql_execute_streaming_chunks_response'] ?? 0,
      'materialized_responses_total': metrics['rpc_sql_execute_materialized_response'] ?? 0,
      'cancel_requests_total': metrics['stream_cancel_request'] ?? 0,
      'backpressure_cancels_total': metrics['stream_cancel_backpressure'] ?? 0,
      'batched_path_total': metrics['streaming_batched_path'] ?? 0,
      'single_chunk_path_total': metrics['streaming_single_chunk_path'] ?? 0,
      'native_batched_path_observable': diagnostics['native_batched_path_observable'] ?? false,
      'native_path_inference': diagnostics['native_path_inference'],
      'worker_hold_avg_ms': (metrics['streaming_worker_hold_avg_time_ms'] as num?)?.toInt() ?? 0,
      'worker_hold_p95_ms': (metrics['streaming_worker_hold_p95_time_ms'] as num?)?.toInt() ?? 0,
      'worker_hold_max_recent_ms': (metrics['streaming_worker_hold_max_recent_time_ms'] as num?)?.toInt() ?? 0,
      'worker_hold_sample_count': metrics['streaming_worker_hold_sample_count'] ?? 0,
    };
  }
}
