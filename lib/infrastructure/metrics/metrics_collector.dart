import 'dart:async';
import 'dart:collection';
import 'dart:developer' as developer;

import 'package:plug_agente/domain/entities/query_metrics.dart';
import 'package:plug_agente/domain/repositories/i_metrics_collector.dart';

/// Servico para coletar e gerenciar metricas de performance.
///
/// Chaves em [_eventCounters] sao estaveis para exportacao (ex.: OpenTelemetry).
class MetricsCollector implements IMetricsCollector {
  MetricsCollector();

  static const String _timeoutCancelSuccessCounter = 'timeout_cancel_success';
  static const String _timeoutCancelFailureCounter = 'timeout_cancel_failure';
  static const String _transactionRollbackFailureCounter =
      'transaction_rollback_failure';
  static const String _idempotencyFingerprintMismatchCounter =
      'idempotency_fingerprint_mismatch';
  static const String _multiResultPoolVacuousFallbackCounter =
      'multi_result_pool_vacuous_fallback';
  static const String _multiResultDirectStillVacuousCounter =
      'multi_result_direct_still_vacuous';
  static const String _transactionalBatchDirectPathCounter =
      'transactional_batch_direct_path';

  static const int _maxMetrics = 10000;

  final List<QueryMetrics> _metrics = [];
  final _metricsController = StreamController<QueryMetrics>.broadcast();
  final Map<String, int> _eventCounters = <String, int>{};

  @override
  Stream<QueryMetrics> get metricsStream => _metricsController.stream;

  @override
  List<QueryMetrics> get metrics => List.unmodifiable(_metrics);

  /// Numero de metricas coletadas.
  int get count => _metrics.length;
  int get timeoutCancelSuccessCount =>
      _eventCounters[_timeoutCancelSuccessCounter] ?? 0;
  int get timeoutCancelFailureCount =>
      _eventCounters[_timeoutCancelFailureCounter] ?? 0;
  int get transactionRollbackFailureCount =>
      _eventCounters[_transactionRollbackFailureCounter] ?? 0;
  int get idempotencyFingerprintMismatchCount =>
      _eventCounters[_idempotencyFingerprintMismatchCounter] ?? 0;
  int get multiResultPoolVacuousFallbackCount =>
      _eventCounters[_multiResultPoolVacuousFallbackCounter] ?? 0;
  int get multiResultDirectStillVacuousCount =>
      _eventCounters[_multiResultDirectStillVacuousCounter] ?? 0;
  int get transactionalBatchDirectPathCount =>
      _eventCounters[_transactionalBatchDirectPathCounter] ?? 0;

  Map<String, int> get eventCounters =>
      UnmodifiableMapView<String, int>(_eventCounters);

  /// Limpa todas as metricas.
  void clear() {
    _metrics.clear();
    _eventCounters.clear();
  }

  void recordTimeoutCancelSuccess() =>
      _incrementEventCounter(_timeoutCancelSuccessCounter);

  void recordTimeoutCancelFailure() =>
      _incrementEventCounter(_timeoutCancelFailureCounter);

  void recordTransactionRollbackFailure() =>
      _incrementEventCounter(_transactionRollbackFailureCounter);

  void recordIdempotencyFingerprintMismatch() =>
      _incrementEventCounter(_idempotencyFingerprintMismatchCounter);

  void recordMultiResultPoolVacuousFallback() =>
      _incrementEventCounter(_multiResultPoolVacuousFallbackCounter);

  void recordMultiResultDirectStillVacuous() =>
      _incrementEventCounter(_multiResultDirectStillVacuousCounter);

  void recordTransactionalBatchDirectPath() =>
      _incrementEventCounter(_transactionalBatchDirectPathCounter);

  /// Registra uma metrica de sucesso.
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

  /// Registra uma metrica de falha.
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

  @override
  MetricsSummary getSummary({int limit = 100}) {
    final recent = _metrics.length > limit
        ? _metrics.sublist(_metrics.length - limit)
        : _metrics;

    return MetricsSummary.fromList(recent);
  }

  /// Obtem metricas filtradas por sucesso/falha.
  List<QueryMetrics> getMetrics({bool? success}) {
    if (success == null) return List.unmodifiable(_metrics);

    return _metrics.where((m) => m.success == success).toList();
  }

  /// Obtem metricas acima de um tempo de execucao.
  List<QueryMetrics> getSlowQueries({
    Duration threshold = const Duration(seconds: 1),
  }) {
    return _metrics.where((m) => m.executionDuration > threshold).toList()
      ..sort((a, b) => b.executionDuration.compareTo(a.executionDuration));
  }

  /// Registra metrica e notifica listeners.
  void _addMetric(QueryMetrics metric) {
    _metrics.add(metric);
    if (_metrics.length > _maxMetrics) {
      _metrics.removeRange(0, _metrics.length - _maxMetrics);
    }

    if (!metric.success) {
      developer.log(
        'QueryMetric: ${metric.executionDuration.inMilliseconds}ms, '
        'rows: ${metric.rowsAffected}, success: false',
        name: 'metrics',
        level: 1000,
      );
    }

    if (!_metricsController.isClosed) {
      _metricsController.add(metric);
    }
  }

  void _incrementEventCounter(String counter) {
    _eventCounters[counter] = (_eventCounters[counter] ?? 0) + 1;
  }

  /// Exporta metricas para JSON.
  List<Map<String, dynamic>> exportToJson() {
    return _metrics.map((m) => m.toMap()).toList();
  }

  /// Dispose do controller.
  void dispose() {
    _metricsController.close();
  }
}
