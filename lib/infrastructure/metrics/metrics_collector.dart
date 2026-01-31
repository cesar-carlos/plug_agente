import 'dart:async';
import 'dart:developer' as developer;

import 'package:plug_agente/domain/entities/query_metrics.dart';

/// Serviço para coletar e gerenciar métricas de performance.
class MetricsCollector {
  MetricsCollector._();

  static MetricsCollector? _instance;
  static MetricsCollector get instance => _instance ??= MetricsCollector._();

  final List<QueryMetrics> _metrics = [];
  final _metricsController = StreamController<QueryMetrics>.broadcast();

  /// Stream de novas métricas.
  Stream<QueryMetrics> get metricsStream => _metricsController.stream;

  /// Lista de todas as métricas coletadas.
  List<QueryMetrics> get metrics => List.unmodifiable(_metrics);

  /// Número de métricas coletadas.
  int get count => _metrics.length;

  /// Limpa todas as métricas.
  void clear() {
    _metrics.clear();
  }

  /// Registra uma métrica de sucesso.
  void recordSuccess({
    required String queryId,
    required String query,
    required Duration executionDuration,
    required int rowsAffected,
    required int columnCount,
  }) {
    final metric = QueryMetrics.success(
      queryId: queryId,
      query: query,
      executionDuration: executionDuration,
      rowsAffected: rowsAffected,
      columnCount: columnCount,
    );

    _addMetric(metric);
  }

  /// Registra uma métrica de falha.
  void recordFailure({
    required String queryId,
    required String query,
    required Duration executionDuration,
    required String errorMessage,
  }) {
    final metric = QueryMetrics.failure(
      queryId: queryId,
      query: query,
      executionDuration: executionDuration,
      errorMessage: errorMessage,
    );

    _addMetric(metric);
  }

  /// Obtém resumo das últimas N métricas.
  MetricsSummary getSummary({int limit = 100}) {
    final recent = _metrics.length > limit
        ? _metrics.sublist(_metrics.length - limit)
        : _metrics;

    return MetricsSummary.fromList(recent);
  }

  /// Obtém métricas filtradas por sucesso/falha.
  List<QueryMetrics> getMetrics({bool? success}) {
    if (success == null) return List.unmodifiable(_metrics);

    return _metrics.where((m) => m.success == success).toList();
  }

  /// Obtém métricas acima de um tempo de execução.
  List<QueryMetrics> getSlowQueries({
    Duration threshold = const Duration(seconds: 1),
  }) {
    return _metrics.where((m) => m.executionDuration > threshold).toList()
      ..sort((a, b) => b.executionDuration.compareTo(a.executionDuration));
  }

  /// Registra métrica e notifica listeners.
  void _addMetric(QueryMetrics metric) {
    _metrics.add(metric);

    // Log estruturado para debugging
    developer.log(
      'QueryMetric: ${metric.executionDuration.inMilliseconds}ms, rows: ${metric.rowsAffected}, success: ${metric.success}',
      name: 'metrics',
      level: metric.success
          ? 500
          : 1000, // INFO para sucesso, SEVERE para falha
    );

    // Notificar listeners
    if (!_metricsController.isClosed) {
      _metricsController.add(metric);
    }
  }

  /// Exporta métricas para JSON.
  List<Map<String, dynamic>> exportToJson() {
    return _metrics.map((m) => m.toMap()).toList();
  }

  /// Dispose do controller.
  void dispose() {
    _metricsController.close();
  }
}
