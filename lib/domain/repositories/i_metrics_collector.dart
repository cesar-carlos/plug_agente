import 'package:plug_agente/domain/entities/query_metrics.dart';

/// Per-query stream and summaries. Event-style counters may exist only on the
/// concrete collector registered in DI.
abstract class IMetricsCollector {
  Stream<QueryMetrics> get metricsStream;
  List<QueryMetrics> get metrics;
  MetricsSummary getSummary({int limit = 100});
}
