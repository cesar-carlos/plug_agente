import 'dart:async';

import 'package:plug_agente/domain/repositories/i_deprecation_metrics_collector.dart';

/// Collects deprecation usage metrics for observability and removal planning.
class DeprecationMetricsCollector implements IDeprecationMetricsCollector {
  DeprecationMetricsCollector();

  int _preserveSqlUsageCount = 0;
  final StreamController<void> _updates = StreamController<void>.broadcast(sync: true);

  @override
  Stream<void> get updates => _updates.stream;

  @override
  int get preserveSqlUsageCount => _preserveSqlUsageCount;

  @override
  void recordPreserveSqlUsage({
    String? requestId,
    String? method,
  }) {
    _preserveSqlUsageCount++;
    if (!_updates.isClosed) {
      _updates.add(null);
    }
  }
}
