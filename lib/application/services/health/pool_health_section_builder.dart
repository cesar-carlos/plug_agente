import 'package:plug_agente/core/constants/connection_constants.dart';
import 'package:plug_agente/domain/repositories/i_odbc_connection_settings.dart';

final class PoolHealthSectionBuilder {
  const PoolHealthSectionBuilder({IOdbcConnectionSettings? odbcSettings}) : _odbcSettings = odbcSettings;

  final IOdbcConnectionSettings? _odbcSettings;

  Map<String, Object?> build({
    required Map<String, Object?> metrics,
    required Map<String, Object?> poolDiagnostics,
    int? poolActiveCount,
    String? driverType,
  }) {
    final directFallbacks = metrics['direct_connection_fallback'] as int? ?? 0;
    final nativeFallbacks = metrics['odbc_native_pool_fallback'] as int? ?? 0;

    return {
      'size': _odbcSettings?.poolSize ?? ConnectionConstants.poolSize,
      'active_count': poolActiveCount,
      'acquire_timeout_seconds': ConnectionConstants.defaultPoolAcquireTimeout.inSeconds,
      'native_pool_exposed': poolDiagnostics['native_pool_exposed'] ?? false,
      'strategy': poolDiagnostics['strategy'] ?? 'lease',
      'effective_strategy': poolDiagnostics['effective_strategy'] ?? poolDiagnostics['strategy'] ?? 'lease',
      'driver_type': driverType,
      'experimental_enabled': poolDiagnostics['experimental_enabled'] ?? false,
      'native_eligible': poolDiagnostics['native_eligible'],
      'native_circuit_open': poolDiagnostics['native_circuit_open'] ?? false,
      'native_circuit_failures': poolDiagnostics['native_circuit_failures'] ?? 0,
      'native_circuit_disabled_until': poolDiagnostics['native_circuit_disabled_until'],
      'native_options_skip_total': poolDiagnostics['native_options_skip_total'] ?? 0,
      'native_execution_fallback_total': poolDiagnostics['native_execution_fallback_total'] ?? 0,
      'native_compatible_acquire_attempt_total':
          poolDiagnostics['native_compatible_acquire_attempt_total'] ??
          metrics['odbc_native_compatible_acquire_attempt'] ??
          0,
      'native_compatible_acquire_success_total':
          poolDiagnostics['native_compatible_acquire_success_total'] ??
          metrics['odbc_native_compatible_acquire_success'] ??
          0,
      'native_skip_reason': poolDiagnostics['native_skip_reason'],
      'fallbacks_total': directFallbacks + nativeFallbacks,
      'direct_fallbacks_total': directFallbacks,
      'native_fallbacks_total': nativeFallbacks,
      'lease_active_count': poolDiagnostics['lease_active_count'] ?? 0,
      'native_active_count': poolDiagnostics['native_active_count'] ?? 0,
      'pool_discard_inflight': metrics['pool_discard_inflight'] ?? 0,
      'pool_discard_reconciliation_stale_total': metrics['pool_discard_reconciliation_stale'] ?? 0,
    };
  }
}
