import 'package:plug_agente/domain/entities/query_metrics.dart';

abstract class IMetricsCollector {
  Stream<QueryMetrics> get metricsStream;
  List<QueryMetrics> get metrics;
  MetricsSummary getSummary({int limit = 100});
}
