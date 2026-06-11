import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_direct_connection_limiter_diagnostics.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';

final class DirectConnectionHealthSectionBuilder {
  const DirectConnectionHealthSectionBuilder({
    IDirectConnectionLimiterDiagnostics? directConnectionLimiter,
    IOdbcConnectionSettings? odbcSettings,
  }) : _directConnectionLimiter = directConnectionLimiter,
       _odbcSettings = odbcSettings;

  final IDirectConnectionLimiterDiagnostics? _directConnectionLimiter;
  final IOdbcConnectionSettings? _odbcSettings;

  Map<String, Object?> build(Map<String, Object?> metrics) {
    final limiter = _directConnectionLimiter;
    final poolSize = _odbcSettings?.poolSize;

    return {
      'active_count': limiter?.activeCount ?? metrics['direct_connection_active_count'] ?? 0,
      'max_concurrent': limiter?.maxConcurrent,
      'effective_cap':
          limiter?.maxConcurrent ??
          (poolSize != null ? ConnectionConstants.directOdbcConnectionConcurrency(poolSize) : null),
      'override_requested': ConnectionConstants.directOdbcConnectionMaxConcurrentOverride,
      'override_exceeds_pool': ConnectionConstants.directOdbcConnectionOverrideExceedsPool(poolSize),
      'capacity_strategy': ConnectionConstants.directOdbcConnectionCapacityStrategy(),
      'pool_size_reference': poolSize,
      'is_saturated': limiter?.isSaturated ?? false,
      'by_operation_class': limiter?.getOperationClassDiagnostics() ?? const <String, Object?>{},
      'opened_total': limiter?.openedTotal ?? metrics['direct_connection_opened'] ?? 0,
      'closed_total': limiter?.closedTotal ?? metrics['direct_connection_closed'] ?? 0,
      'acquire_timeouts_total': metrics['direct_connection_acquire_timeout'] ?? 0,
      'wait_avg_ms': metrics['direct_connection_wait_avg_time_ms'] ?? 0.0,
      'wait_p95_ms': metrics['direct_connection_wait_p95_time_ms'] ?? 0,
      'wait_p99_ms': metrics['direct_connection_wait_p99_time_ms'] ?? 0,
      'wait_sample_count': metrics['direct_connection_wait_sample_count'] ?? 0,
    };
  }
}
